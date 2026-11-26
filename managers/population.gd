class_name Population
extends RefCounted

# Everything that lives in the world and the termite colonies: spawning fireflies, spiders,
# beetles and centipedes (and bringing them back after they die), and the termite colonies
# (the queen, soldiers and workers, what happens when a queen dies, and turning a dead mound grey).
# Also remembers each living colony's wounded queen and stockpile so they can be saved.
# main.gd calls process_grey() every frame; content.gd calls the spawn_ functions as regions are built.

var m: Main

func setup(main: Main) -> void:
	m = main

# What a save needs to remember about colonies that are still alive.
func live_colony_state() -> Array:
	var out: Array = []
	for cell in m.terrain.mound_cells:
		var col: Dictionary = m.terrain.mound_cells[cell]
		if col.is_empty() or col.get("dead", false):
			continue
		for c in Registry.of("creatures"):
			if c is TermiteQueen and (c as TermiteQueen).colony == col:
				col["saved_qhp"] = (c as Creature).health
		var stock: Dictionary = col["stock"]
		var stocked := int(stock.get("sugar", 0)) + int(stock.get("pebble", 0)) + int(stock.get("fiber", 0)) > 0
		var max_hp := 1500.0 if col.get("great", false) else 400.0
		var hurt: bool = col.has("saved_qhp") and float(col["saved_qhp"]) < max_hp - 0.5
		if stocked or hurt:
			out.append({"cell": cell, "stock": stock.duplicate(), "qhp": float(col.get("saved_qhp", max_hp))})
	return out

# When a queen is unloaded (you walked away), remember how hurt she was.
func remember_queen(q: TermiteQueen, col: Dictionary) -> void:
	if not col["dead"]:
		col["saved_qhp"] = q.health

func restore_live_state(list: Array) -> void:
	for e in list:
		var col: Dictionary = m.terrain.mound_at_cell(e["cell"])
		if col.is_empty() or col.get("dead", false):
			continue
		var stock: Dictionary = col["stock"]
		for k in e["stock"]:
			stock[k] = int(e["stock"][k])
		col["saved_qhp"] = float(e["qhp"])

func spawn_firefly(pos: Vector3) -> void:
	var f := Firefly.new()
	f.ant = m.ant
	f.ground_at = m.terrain.ground_height
	f.is_loaded = m.stream.ground_ready
	f.home = pos
	f.died.connect(_on_creature_died)
	m.stream.region_node(m.stream.region_key(pos.x, pos.z)).add_child(f)
	f.global_position = pos
	f.set_active(m.atmos.night_creatures)

func spawn_dragonfly(pos: Vector3) -> Creature:
	var d := Dragonfly.new()
	d.ant = m.ant
	d.ground_at = m.terrain.ground_height
	d.is_loaded = m.stream.ground_ready
	d.home = pos
	d.died.connect(_on_creature_died)
	m.stream.region_node(m.stream.region_key(pos.x, pos.z)).add_child(d)
	d.global_position = pos
	d.set_active(not m.atmos.night_creatures)   # it hunts by day
	return d

func spawn_fish(pos: Vector3, lake: Dictionary, aggressive: bool) -> Fish:
	var f := Fish.new()
	f.ant = m.ant
	f.terrain = m.terrain
	f.lake = lake
	f.aggressive = aggressive
	f.home = pos
	f.died.connect(_on_creature_died)
	m.stream.region_node(m.stream.region_key(pos.x, pos.z)).add_child(f)
	f.global_position = pos
	return f

func spawn_spider(pos: Vector3) -> Creature:
	var sp := Spider.new()
	sp.ant = m.ant
	sp.queen_getter = func(): return m.queen
	sp.ground_at = m.terrain.ground_height
	sp.is_loaded = m.stream.ground_ready
	sp.home = pos
	sp.died.connect(_on_creature_died)
	m.stream.region_node(m.stream.region_key(pos.x, pos.z)).add_child(sp)
	sp.global_position = pos
	sp.set_active(m.atmos.night_creatures)
	return sp

# Brings a creature back, unless its region has been forgotten (a new one appears with the region).
func respawn_creature(home: Vector3, kind: String) -> void:
	if not m.stream.region_done.has(m.stream.region_key(home.x, home.z)):
		return
	match kind:
		"firefly":
			spawn_firefly(home)
		"spider":
			spawn_spider(home)
		"beetle":
			spawn_beetle(home)
		"centipede":
			spawn_centipede(home)
		"dragonfly":
			spawn_dragonfly(home)
		"fish":
			for lk in m.terrain.pools_at(home.x, home.z):
				if lk.get("lake", false):
					spawn_fish(home, lk, randf() < Main.FISH_AGGRESSIVE_SHARE)

func spawn_beetle(pos: Vector3) -> Creature:
	var b := Beetle.new()
	b.ant = m.ant
	b.queen_getter = func(): return m.queen
	b.ground_at = m.terrain.ground_height
	b.is_loaded = m.stream.ground_ready
	b.home = pos
	b.died.connect(_on_creature_died)
	m.stream.region_node(m.stream.region_key(pos.x, pos.z)).add_child(b)
	b.global_position = pos
	b.set_active(not m.atmos.night_creatures)
	return b

func spawn_centipede(pos: Vector3) -> Creature:
	var c := Centipede.new()
	c.ant = m.ant
	c.queen_getter = func(): return m.queen
	c.ground_at = m.terrain.ground_height
	c.is_loaded = m.stream.ground_ready
	c.home = pos
	c.died.connect(_on_creature_died)
	m.stream.region_node(m.stream.region_key(pos.x, pos.z)).add_child(c)
	c.global_position = pos
	c.set_active(m.atmos.night_creatures)
	return c

# A creature died: drop its loot, and for fireflies, bring a new one back later.
func _on_creature_died(c: Creature) -> void:
	Effects.death_puff(m, c.global_position + Vector3(0, 0.3, 0), 2.5 if c.is_boss else 1.0)
	var kind := c.loot_kind()
	if c.is_minion:
		return   # a boss's helper: no loot, no respawn
	if c.is_boss:
		drop_boss_loot(c, kind)
		return   # bosses do not come back
	if kind != "":
		var p := Pickup.new()
		p.kind = kind
		p.amount = randi_range(1, 3)
		m.add_child(p)
		p.global_position = c.global_position
	var home := c.home
	if c is TermiteQueen:
		colony_destroyed((c as TermiteQueen).colony)
		return
	elif c is TermiteWorker:
		var wc: Dictionary = (c as TermiteWorker).colony
		wc["workers"] = maxi(0, int(wc["workers"]) - 1)
		return
	elif c is TermiteSoldier:
		var sc: Dictionary = (c as TermiteSoldier).colony
		sc["soldiers"] = maxi(0, int(sc["soldiers"]) - 1)
		return
	if c is Firefly:
		m.get_tree().create_timer(Main.FIREFLY_RESPAWN_SECONDS).timeout.connect(respawn_creature.bind(home, "firefly"))
	elif c is Spider:
		m.get_tree().create_timer(Main.SPIDER_RESPAWN_SECONDS).timeout.connect(respawn_creature.bind(home, "spider"))
	elif c is Beetle:
		m.get_tree().create_timer(Main.BEETLE_RESPAWN_SECONDS).timeout.connect(respawn_creature.bind(home, "beetle"))
	elif c is Centipede:
		m.get_tree().create_timer(Main.CENTIPEDE_RESPAWN_SECONDS).timeout.connect(respawn_creature.bind(home, "centipede"))
	elif c is Dragonfly:
		m.get_tree().create_timer(Main.DRAGONFLY_RESPAWN_SECONDS).timeout.connect(respawn_creature.bind(home, "dragonfly"))
	elif c is Fish:
		m.get_tree().create_timer(Main.FISH_RESPAWN_SECONDS).timeout.connect(respawn_creature.bind(home, "fish"))

# ---------- Termite colonies ----------
# When the region holding a mound is built, its colony moves in: the queen in her cell, a few
# soldiers at the guard posts, and workers. The queen keeps laying more (up to a limit). When
# she dies the colony is finished: nothing more spawns, what is left fades, and the mound
# turns grey.

const GREY_CHUNKS_PER_FRAME := 2

var grey_jobs: Array = []   # chunks of a dead mound waiting to turn grey

func region_colony(job: Dictionary) -> void:
	var rect := m.stream.region_rect(job["key"])
	var seen := {}
	for corner in [rect.position, rect.position + Vector2(rect.size.x, 0), rect.position + Vector2(0, rect.size.y), rect.end]:
		var cell := Vector2i(floori(corner.x / Main.MOUND_CELL), floori(corner.y / Main.MOUND_CELL))
		if seen.has(cell):
			continue
		seen[cell] = true
		var col := m.terrain.mound_at_cell(cell)
		if col.is_empty():
			continue
		if rect.has_point(Vector2(float(col["x"]), float(col["z"]))):
			spawn_colony(col, job["key"])

func spawn_colony(col: Dictionary, key: Vector2i) -> void:
	col["workers"] = 0
	col["soldiers"] = 0
	if col["dead"]:
		return
	var rn := m.stream.region_node(key)
	var q := TermiteQueen.new()
	q.colony = col
	q.spawn_cb = spawn_termite
	TermiteQueen.ward_message = func(): m.show_message("A shimmering ward protects the Great Mound queen. Gather biome relics to break it.")
	q.is_loaded = m.stream.ground_ready
	q.ant = m.ant
	q.home = col["queen_pos"]
	q.died.connect(_on_creature_died)
	rn.add_child(q)
	if col.has("saved_qhp"):
		q.health = minf(float(col["saved_qhp"]), q.max_health)   # a wounded queen stays wounded
	q.tree_exiting.connect(remember_queen.bind(q, col))
	q.global_position = col["queen_pos"]
	q.rotation.y = 0.6
	# Dim lights so the royal cell and the great hall are not pitch black.
	for lp in [Vector3(col["royal"]), Vector3(col["hall"])]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.5)
		l.light_energy = 1.2
		l.omni_range = 16.0
		rn.add_child(l)
		l.global_position = lp + Vector3(0, 2.0, 0)
	for i in (14 if col.get("great", false) else 6):
		spawn_termite(col, "soldier")
	for i in 4:
		spawn_termite(col, "worker")

func spawn_termite(col: Dictionary, kind: String) -> void:
	if col["dead"]:
		return
	var key := m.stream.region_key(float(col["x"]), float(col["z"]))
	if not m.stream.region_nodes.has(key):
		return
	var rn := m.stream.region_node(key)
	var c: Crawler
	var pos: Vector3
	if kind == "soldier":
		var s := TermiteSoldier.new()
		s.colony = col
		var posts: Array = col["posts"]
		pos = posts[randi() % posts.size()]
		col["soldiers"] = int(col["soldiers"]) + 1
		c = s
	else:
		var w := TermiteWorker.new()
		w.colony = col
		w.wander_min = float(col["R"]) + 6.0
		w.wander_radius = 45.0
		pos = col["entrance_in"]
		col["workers"] = int(col["workers"]) + 1
		c = w
	c.ant = m.ant
	c.queen_getter = func(): return null
	c.ground_at = m.terrain.ground_height
	c.is_loaded = m.stream.ground_ready
	c.home = pos if kind == "soldier" else Vector3(col["center"])
	c.died.connect(_on_creature_died)
	rn.add_child(c)
	c.global_position = pos + Vector3(randf_range(-1.0, 1.0), 0.6, randf_range(-1.0, 1.0))

func colony_destroyed(col: Dictionary) -> void:
	if col["dead"]:
		return
	col["alive"] = false
	col["dead"] = true
	m.progression.colony_destroyed(col)
	m.show_message("The termite queen is dead. The colony is finished!")
	# Everything the workers stored spills out of the royal cell, plus a reward of sugar.
	var qp: Vector3 = col["queen_pos"]
	var stock: Dictionary = col["stock"]
	stock["sugar"] = int(stock.get("sugar", 0)) + 6
	for k in stock:
		var left := int(stock[k])
		while left > 0:
			var n := mini(left, 4)
			left -= n
			var p := Pickup.new()
			p.kind = k
			p.amount = n
			m.add_child(p)
			p.global_position = qp + Vector3(randf_range(-2.0, 2.0), 2.0, randf_range(-2.0, 2.0))
		stock[k] = 0
	# Queue every loaded chunk of the mound to turn grey.
	var center: Vector3 = col["center"]
	var reach := float(col["R"]) + 30.0
	var lo := Vector2i(floori((center.x - reach) / Chunk.SIZE), floori((center.z - reach) / Chunk.SIZE))
	var hi := Vector2i(floori((center.x + reach) / Chunk.SIZE), floori((center.z + reach) / Chunk.SIZE))
	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			for cy in range(Main.CY_MIN, Main.HEIGHT_CHUNKS):
				var cp := Vector3i(cx, cy, cz)
				if m.world.chunks.has(cp):
					grey_jobs.append(cp)

func process_grey() -> void:
	var n := 0
	while not grey_jobs.is_empty() and n < GREY_CHUNKS_PER_FRAME:
		var cp: Vector3i = grey_jobs.pop_front()
		var ch: Chunk = m.world.get_chunk(cp)
		if ch == null:
			continue
		var changed := false
		for lx in Chunk.SIZE:
			for ly in Chunk.SIZE:
				for lz in Chunk.SIZE:
					if ch.get_material(lx, ly, lz) == Blocks.MOUND:
						ch.set_voxel(lx, ly, lz, ch.get_density(lx, ly, lz), Blocks.DEAD_MOUND)
						changed = true
		n += 1
		if changed:
			m.save.note_edited(cp)   # so the grey colour is kept in your save
			m.stream.queue_remesh([cp], Vector3(cp * Chunk.SIZE))

# ---------- Tunnel worms ----------
# While you dig deep underground, the rock sometimes bursts open and a worm lunges out. At most one
# at a time, with a long rest after each, never near a termite mound, and never near the surface.

const WORM_CHANCE := 0.004          # chance per dig stroke (holding the button digs about 7 strokes a second)
const WORM_COOLDOWN := 90.0         # seconds before another can ambush you
const WORM_MIN_DEPTH := 10.0        # only this far below the surface
const WORM_MAX_ALIVE := 1
const WORM_BOSS_CHANCE := 0.1      # one ambush in ten is the Elder Tunnel Worm
const WORM_GRACE := 60.0            # none in your first minute of play

var next_worm_time := WORM_GRACE

func now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func worms_alive() -> int:
	var n := 0
	for c in Registry.of("creatures"):
		if c is TunnelWorm:
			n += 1
	return n

# Called after every dig stroke with the middle of the new hole.
func maybe_worm(point: Vector3) -> void:
	if now_seconds() < next_worm_time or randf() > WORM_CHANCE:
		return
	if worms_alive() >= WORM_MAX_ALIVE or m.atmos.openness > 0.5:
		return
	if point.y > m.terrain.ground_height(point.x, point.z) - WORM_MIN_DEPTH:
		return
	var mound := m.terrain.mound_near(point.x, point.z)
	if not mound.is_empty() and Vector2(point.x - float(mound["x"]), point.z - float(mound["z"])).length() < float(mound["R"]) + 30.0:
		return
	spawn_worm(point, randf() < WORM_BOSS_CHANCE)

func spawn_worm(pos: Vector3, boss: bool = false) -> void:
	next_worm_time = now_seconds() + WORM_COOLDOWN
	var w := TunnelWorm.new()
	w.ant = m.ant
	w.queen_getter = func(): return m.queen
	w.ground_at = m.terrain.ground_height
	w.is_loaded = m.stream.ground_ready
	w.home = pos
	w.died.connect(_on_creature_died)
	m.stream.region_node(m.stream.region_key(pos.x, pos.z)).add_child(w)
	w.global_position = pos + Vector3(0, 0.4, 0)
	burst_dust(pos)
	if boss:
		w.make_boss("Elder Tunnel Worm", 1.9, 6.0, 1.6, 0.5)
		w.collapse_requested.connect(_on_worm_collapse)
		m.show_message("The ground shudders. Something huge breaks out of the rock!")
	else:
		m.show_message("The rock bursts open. A tunnel worm lunges out!")

# A puff of rock dust where the worm breaks out.
func burst_dust(pos: Vector3) -> void:
	Effects.impact(m, pos, 2.2, Color(0.5, 0.43, 0.36))

# ---------- Bosses ----------
# A boss is a big, tough version of a creature that sits where a normal one would. When you get
# close its health bar appears at the bottom of the screen. It drops a lot of loot and never returns.

const BOSS_ENGAGE_RANGE := 40.0
const BOSS_KINDS := ["spider", "beetle", "centipede"]

var current_boss: Creature = null

# Spawns a boss of the given kind ("spider", "beetle", "centipede").
func spawn_boss(kind: String, pos: Vector3) -> void:
	var c: Creature = null
	match kind:
		"spider":
			c = spawn_spider(pos)
			c.make_boss("Broodmother Spider", 2.6, 7.0, 1.7, 0.78)
			c.boss_loot = 60
			(c as Spider).summon_requested.connect(_on_brood_summoned)
		"beetle":
			c = spawn_beetle(pos)
			c.make_boss("Ironback Beetle", 2.4, 5.0, 1.8, -0.35)
		"centipede":
			c = spawn_centipede(pos)
			c.make_boss("Elder Centipede", 2.4, 7.0, 1.7, 0.55)
	if c != null:
		c.set_active(true)   # a boss is always out, day or night

func drop_boss_loot(c: Creature, kind: String) -> void:
	if kind == "":
		kind = "sugar"
	var piles := maxi(1, ceili(float(c.boss_loot) / 10.0))
	for i in piles:
		var p := Pickup.new()
		p.kind = kind
		p.amount = 10
		m.add_child(p)
		p.global_position = c.global_position + Vector3(randf_range(-1.5, 1.5), 1.0, randf_range(-1.5, 1.5))
	m.show_message("BOSS DEFEATED: " + c.boss_name)

# Called every frame: shows the bar of the nearest boss that is close enough.
func update_boss(delta: float) -> void:
	var best: Creature = null
	var best_d := BOSS_ENGAGE_RANGE
	for c in Registry.of("creatures"):
		var cr := c as Creature
		if not cr.is_boss or not cr.active:
			continue
		var d := cr.global_position.distance_to(m.ant.global_position)
		if d < best_d:
			best_d = d
			best = cr
	if best != current_boss and best != null:
		m.show_message("BOSS: " + best.boss_name)
		if not best.intro_done:
			best.intro_done = true
			m.ant.focus_on(best, 1.8)   # the camera swings to the boss the first time you come near
	current_boss = best
	m.ui.update_boss_bar(delta, best)

# The Broodmother calls her young: smaller, weaker spiders that attack you at once.
func _on_brood_summoned(boss: Spider, count: int) -> void:
	m.show_message("The Broodmother calls her brood!")
	for i in count:
		var a := TAU * float(i) / float(count) + randf() * 0.4
		var p := boss.global_position + Vector3(cos(a) * 4.5, 0.5, sin(a) * 4.5)
		p.y = m.terrain.ground_height(p.x, p.z) + 0.5
		var s := spawn_spider(p) as Spider
		s.is_minion = true
		s.nocturnal = false
		s.max_health = 40.0
		s.health = 40.0
		s.size = 0.65
		s.body_root.scale = Vector3.ONE * 0.65
		s.set_active(true)
		s.state = Spider.State.CHASE
		boss.brood.append(s)

# The Elder Tunnel Worm bursts up and shakes the tunnel roof loose near you (underground only).
func _on_worm_collapse(point: Vector3) -> void:
	if m.atmos.openness > 0.5:
		return
	var a := randf() * TAU
	var spot := point + Vector3(cos(a) * 7.0, 3.5, sin(a) * 7.0)   # beside and above you, never on you
	var dirty := m.world.fill_sphere(spot, 3.2)
	if dirty.is_empty():
		return
	m.stream.mark_edited(dirty)
	m.stream.queue_remesh(dirty, spot)
	m.content.wake_pickups(spot, 4.2)
	m.water.mark_water_dirty(spot, 4.2)
	m.show_message("The burst shakes the roof loose. Rock falls nearby!")
