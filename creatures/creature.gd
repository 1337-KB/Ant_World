class_name Creature
extends Node3D

# The base for every creature (firefly, spider, beetle...). It holds what they all share:
# health, taking damage, dying, and dropping loot. Each animal extends this and adds its own
# behavior in _physics_process, usually as a small state machine.

signal died(creature: Creature)

var max_health := 30.0
var health := 30.0
var nocturnal := false      # true for creatures that only come out at night
var diurnal := false       # true for creatures that only come out by day
var active := true          # inactive creatures are hidden and cannot be hit (fireflies by day)
var home := Vector3.ZERO     # where it lives; wandering stays near here
var is_loaded: Callable      # (position) -> true when the ground there exists. Set by main.
var ant: Ant                 # the player, set when it is spawned
var ground_at: Callable      # (x, z) -> ground height, set when it is spawned
var hit_radius := 0.0        # a big body (the termite queen) is hit anywhere within this of its middle
var hit_offset := Vector3.ZERO   # where that middle is, from the creature's origin, in its own directions

# Bosses: a big, tough version of a creature. The boss bar at the bottom of the screen replaces
# the little bar above its head. Set up by make_boss() right after it is spawned.
var is_boss := false
var boss_name := ""
var size := 1.0              # body scale; reach (bite range) grows with it
var damage_mult := 1.0       # how much harder it hits than the normal creature
var is_minion := false      # a helper summoned by a boss: no loot, never respawns
var boss_loot := 40         # how many units of its loot a boss drops
var intro_done := false     # the camera has already swung to this boss when you first came near
var ring: MeshInstance3D      # red warning disc on the ground, for boss moves you can dodge
var enraged := false         # below half health a boss hits harder

func make_boss(title: String, scale_to: float, health_mult: float, damage: float, hue_shift: float = 0.0) -> void:
	is_boss = true
	nocturnal = false   # bosses are out day and night
	diurnal = false
	boss_name = title
	size = scale_to
	max_health *= health_mult
	health = max_health
	damage_mult = damage
	var br = get("body_root")
	if br is Node3D:
		(br as Node3D).scale = Vector3.ONE * size
	if hit_radius <= 0.0:
		hit_radius = 1.3
		hit_offset = Vector3(0, 0.9, 0)
	hit_radius *= size
	hit_offset *= size
	bar_height *= size
	if hue_shift != 0.0:
		tint_boss(self, hue_shift, {})

func hit_center() -> Vector3:
	return global_position + global_transform.basis * hit_offset

func _ready() -> void:
	Registry.add(self, "creatures")
	health = max_health

func set_active(value: bool) -> void:
	active = value
	visible = value

# A health bar floats over any creature you hurt, for a few seconds after the last hit.
const BAR_SHOW_TIME := 4.0
var bar: Label3D
var bar_time := 0.0
var bar_height := 1.6       # how high above its origin the bar floats
var bar_scale := 1.0        # bigger creatures get a bigger bar

func show_bar() -> void:
	if is_boss:
		return   # the boss bar on screen shows this
	if bar == null:
		bar = Label3D.new()
		bar.font_size = 40
		bar.pixel_size = 0.008 * bar_scale
		bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bar.no_depth_test = true
		bar.fixed_size = false
		bar.outline_size = 10
		bar.position = Vector3(0, bar_height, 0)
		add_child(bar)
	var frac := clampf(health / max_health, 0.0, 1.0)
	var filled := roundi(frac * 10.0)
	bar.text = "[" + "|".repeat(filled) + ".".repeat(10 - filled) + "]  %d / %d" % [maxi(0, ceili(health)), int(max_health)]
	bar.modulate = Color(0.4, 1.0, 0.4).lerp(Color(1.0, 0.3, 0.2), 1.0 - frac)
	bar.visible = health > 0.0
	bar_time = BAR_SHOW_TIME

func _process(delta: float) -> void:
	if bar != null and bar.visible:
		bar_time -= delta
		if bar_time <= 0.0:
			bar.visible = false

func take_damage(amount: float) -> void:
	health -= amount
	if is_boss and not enraged and health < max_health * 0.5:
		enraged = true
		damage_mult *= 1.3
	show_bar()
	on_hurt()
	hit_fx()
	if health <= 0.0:
		die()

# A small puff where it is hit, at most four times a second so a steady spray does not flood the screen.
var last_hit_fx := 0
func hit_fx() -> void:
	var now := Time.get_ticks_msec()
	if now - last_hit_fx < 250 or not is_inside_tree() or not visible:
		return
	last_hit_fx = now
	Effects.hit_puff(get_parent(), global_position + Vector3(0, 0.4, 0) * maxf(1.0, scale.y))

func on_hurt() -> void:
	pass   # animals override this to flash, flee, or get angry

func die() -> void:
	died.emit(self)
	queue_free()

# Where the ground is under a point, for burrowing and landing. On the surface it is the terrain
# height, so a boss never comes up on a tree, a boulder or anything else you are standing on. In a
# tunnel (you are well below the surface) it follows your own height instead.
func burrow_y(p: Vector3) -> float:
	if ground_at.is_valid():
		var g := float(ground_at.call(p.x, p.z))
		if ant.global_position.y > g - 4.0:
			return g
	return ant.global_position.y

# A warning on the ground marking where a boss move will land: a pulsing red disc with a bright
# edge and rippling lines, plus glowing sparks rising off the rim. Hidden when shown is false.
# When it vanishes after a wide warning, the ground answers with a dust ring (the move landed).
const RING_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float edge = smoothstep(0.84, 0.95, r) * (1.0 - smoothstep(0.97, 1.0, r));
	float ripple = 0.5 + 0.5 * sin(r * 16.0 - TIME * 9.0);
	float beat = 0.8 + 0.2 * sin(TIME * 11.0);
	float fill = 0.10 + 0.10 * ripple * r;
	ALBEDO = vec3(1.0, 0.16, 0.07) + vec3(0.0, 0.35, 0.15) * edge;
	ALPHA = clamp(fill + edge * 0.85, 0.0, 1.0) * beat;
}
"""
static var ring_shader: Shader
var ring_fx: CPUParticles3D
var ring_was_shown := false
var ring_point := Vector3.ZERO
var ring_radius := 1.0

func set_ring(point: Vector3, radius: float, shown: bool) -> void:
	if ring == null:
		if ring_shader == null:
			ring_shader = Shader.new()
			ring_shader.code = RING_SHADER
		ring = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(2.0, 2.0)
		var mat := ShaderMaterial.new()
		mat.shader = ring_shader
		pm.material = mat
		ring.mesh = pm
		ring.top_level = true
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		ring_fx = Effects.make(60, 0.7, 0.28, true,
			[Color(1.0, 0.5, 0.2, 0.0), Color(1.0, 0.35, 0.1, 0.9), Color(1.0, 0.15, 0.05, 0.0)], [0.6, 1.0, 0.0])
		ring_fx.top_level = true
		ring_fx.emitting = false
		ring_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		ring_fx.emission_ring_axis = Vector3.UP
		ring_fx.emission_ring_height = 0.1
		ring_fx.direction = Vector3.UP
		ring_fx.spread = 12.0
		ring_fx.initial_velocity_min = 1.5
		ring_fx.initial_velocity_max = 3.5
		ring_fx.gravity = Vector3(0, 1.0, 0)
		add_child(ring_fx)
	if ring_was_shown and not shown and ring_radius > 2.0:
		Effects.shockwave(get_parent(), ring_point, ring_radius)
	ring_was_shown = shown
	ring.visible = shown
	ring_fx.emitting = shown
	if shown:
		ring_point = point
		ring_radius = radius
		ring.global_position = point + Vector3(0, 0.25, 0)
		ring.scale = Vector3(radius, 1.0, radius)
		ring_fx.global_position = point + Vector3(0, 0.3, 0)
		ring_fx.emission_ring_radius = radius * 0.95
		ring_fx.emission_ring_inner_radius = radius * 0.8

# Gives a boss its own colors so it is easy to tell from the normal creature: every material
# shifts around the color wheel, gets brighter, and gains a faint glowing rim.
func tint_boss(node: Node, hue_shift: float, done: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var old := mi.material_override as StandardMaterial3D
		if old != null:
			if not done.has(old):
				var mat := old.duplicate() as StandardMaterial3D
				var c := old.albedo_color
				mat.albedo_color = Color.from_hsv(fposmod(c.h + hue_shift, 1.0), minf(1.0, c.s * 1.1 + 0.1), clampf(c.v * 1.5 + 0.12, 0.0, 1.0), c.a)
				if old.emission_enabled:
					var e := old.emission
					mat.emission = Color.from_hsv(fposmod(e.h + hue_shift, 1.0), e.s, e.v)
				mat.rim_enabled = true
				mat.rim = 0.5
				mat.rim_tint = 0.4
				done[old] = mat
			mi.material_override = done[old]
	for ch in node.get_children():
		tint_boss(ch, hue_shift, done)

# What this creature drops when it dies ("" for nothing).
func loot_kind() -> String:
	return ""

# ---------- Spreading out ----------
# Without this, a group of the same creature all take the exact same path in a single file.
# Each one gets its own sway, its own speed, and is nudged away from its neighbours.

const SEP_RADIUS := 3.0
var path_phase := randf() * TAU
var path_weave := randf_range(0.15, 0.4)     # how far (radians) its path sways to each side
var path_speed := randf_range(0.88, 1.12)    # its own speed, a little faster or slower
var path_clock := 0.0
var sep_vec := Vector3.ZERO
var sep_timer := randf() * 0.2
var solid := true            # false for flyers: they pass through others
var body_radius := 0.8       # how much room its body takes on the ground (times size)
var reach_radius := 0.0      # how far its legs or body stick out to the side, for steering around trees and rocks (0 = same as body_radius)
var neighbours: Array = []   # solid creatures close by, refreshed a few times a second

# Creatures cannot walk through each other. Each frame, anything overlapping is pushed apart
# along the ground. The queen never moves, so others are pushed around her instead.
func push_apart(delta: float) -> void:
	if not solid:
		return
	sep_timer -= delta
	if sep_timer <= 0.0:
		sep_timer = 0.2
		neighbours.clear()
		sep_vec = Vector3.ZERO
		for c in Registry.of("creatures"):
			var o := c as Creature
			if o == self or not o.solid:
				continue
			var off := global_position - o.global_position
			var d := off.length()
			if d > 8.0 * maxf(size, o.size):
				continue
			neighbours.append(o)
			if o.get_script() == get_script() and d < SEP_RADIUS * size and d > 0.01:
				sep_vec += off / d * (1.0 - d / (SEP_RADIUS * size))
	for o in neighbours:
		if not is_instance_valid(o):
			continue
		var oc := o as Creature
		var off := global_position - oc.global_position
		if absf(off.y) > 3.0 * maxf(size, oc.size):
			continue
		off.y = 0.0
		var d := off.length()
		var need := body_radius * size + oc.body_radius * oc.size
		if d >= need:
			continue
		var dir := off / d if d > 0.01 else Vector3(randf() - 0.5, 0, randf() - 0.5).normalized()
		var share := 1.0 if oc is TermiteQueen else 0.5
		global_position += dir * (need - d) * share

# Takes the direction a creature wants to walk (along the ground, length 1) and returns the one
# it should use. dist_left is how far the goal is, speed is how fast it is moving.
func spread(dir: Vector3, dist_left: float, speed: float, delta: float) -> Vector3:
	path_clock += delta
	var upv := Vector3.UP
	var u = get("up")
	if u is Vector3:
		upv = u
	var out := dir
	if dist_left > 6.0 and speed < 9.0:
		out = out.rotated(upv, sin(path_clock * 0.8 + path_phase) * path_weave)   # weaves while far from the goal
	out += (sep_vec - upv * sep_vec.dot(upv)) * 1.2
	out -= upv * out.dot(upv)
	if out.length() < 0.01:
		return dir
	return out.normalized()

# ---------- Staying out of trees and rocks ----------
# Steering turns a creature away from obstacles ahead, but a wide body (a boss spider's legs) can
# still clip something at its side. So each frame, rays are cast out around it and it is pushed
# away from anything inside its reach. Only big or wide creatures bother.

func keep_clear_of_obstacles(delta: float) -> void:
	var r := reach_radius * size if reach_radius > 0.0 else 0.0
	if r < 1.0 or bool(get("ghost")) or climbing:
		return
	var upv := up
	var from := global_position + upv * (0.9 * maxf(size, 1.0))
	var push := Vector3.ZERO
	for k in 8:
		var a := float(k) / 8.0 * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		var hit: Dictionary = call("cast", from, from + dir * r)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if n.dot(upv) > 0.55:
			continue   # ground or a gentle slope, not an obstacle
		if climb_ok and is_tree(hit):
			continue   # it is about to climb this trunk
		var d := from.distance_to(hit["position"] as Vector3)
		push -= dir * (r - d)
	if push.length() > 0.001:
		global_position += push * minf(1.0, 6.0 * delta)

# ---------- Fire ----------
# Animals fear fire. Near one they drop what they are doing and run away from it, and the one that
# is actually standing in the flames jerks and shudders in pain. Bosses are too big to be scared.

const FIRE_FEAR := 6.0          # how close a fire has to be to scare it
const FIRE_RUN_SPEED := 7.0
const FIRE_PAIN_TIME := 0.35
var scorch := 0.0               # >0 while it is being burned: it shudders
var fear_time := 0.0            # keeps running a moment after it is clear of the flames
var fear_from := Vector3.ZERO

# Fire.gd calls this every frame it burns the creature.
func scorched() -> void:
	scorch = FIRE_PAIN_TIME

func nearest_fire() -> Fire:
	var best: Fire = null
	var best_d := FIRE_FEAR + body_radius * size
	for f in Registry.of("fires"):
		var fire := f as Fire
		if fire == null or fire.out:
			continue
		var d := fire.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = fire
	return best

# Returns true while it is running from a fire (its normal thinking is skipped that frame).
func fire_react(delta: float) -> bool:
	scorch = maxf(0.0, scorch - delta)
	fear_time -= delta
	if is_boss or climbing or bool(get("ghost")) or not active:
		return false
	var fire := nearest_fire()
	if fire != null:
		fear_from = fire.global_position
		fear_time = 0.8
	if fear_time <= 0.0:
		return false
	var away := global_position - fear_from
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
	call("walk_toward", global_position + away.normalized() * 10.0, FIRE_RUN_SPEED, delta)
	return true

# Shudder while burning. Runs after the ground logic sets the body's tilt each frame.
func apply_pain() -> void:
	if scorch <= 0.0:
		return
	var k := scorch / FIRE_PAIN_TIME
	var shake := Basis.from_euler(Vector3(randf_range(-1.0, 1.0) * 0.3 * k, 0.0, randf_range(-1.0, 1.0) * 0.3 * k))
	global_transform.basis = global_transform.basis * shake

# ---------- Climbing trees ----------
# Beetles, spiders and termites can climb trunks when they are hunting you and you are up high.
# Centipedes and worms cannot (they set can_climb to false). While climbing, "up" points away from
# the trunk, so walking "forward along the ground" becomes walking up or down the bark.

var up := Vector3.UP
var forward := Vector3.FORWARD
var fall_speed := 0.0
var can_climb := true
var climbing := false        # currently on a trunk
var climb_ok := false        # this frame trunks count as walkable instead of as walls

# Trees carry a "climbable" tag (set where they are built in content.gd).
func is_tree(hit: Dictionary) -> bool:
	var c = hit.get("collider")
	return c is Node and (c as Node).has_meta("climbable")

# Called at the start of walk_toward. Decides whether trunks are walkable this frame and, when
# already up a tree with nothing to chase, turns the goal into "go back down".
func plan_climb(point: Vector3) -> Vector3:
	climb_ok = false
	if not can_climb or ant == null:
		return point
	var chasing := point.distance_to(ant.global_position) < 3.0
	var ant_y := ant.global_position.y
	if climbing:
		climb_ok = true
		if chasing and ant_y > global_position.y - 1.5:
			return point   # you are level with it or higher: keep going toward you
		return global_position + Vector3.DOWN * 8.0
	if chasing and ant_y > global_position.y + 2.5:
		climb_ok = true
	return point

# Steps onto a trunk when one is right in front and we want to go up it.
func try_mount() -> void:
	if not climb_ok or climbing:
		return
	var r := body_radius * size
	var from := global_position + up * (0.8 * maxf(size, 1.0))
	var hit: Dictionary = call("cast", from, from + forward * (r + 0.8))
	if hit.is_empty() or not is_tree(hit):
		return
	climbing = true
	up = (hit["normal"] as Vector3).normalized()
	global_position = hit["position"]
	cur_speed = 0.0

# Holds the body against the surface it is on: a wall ahead (inside corner), the surface beneath,
# or the edge it is walking around (outside corner). Lets go when there is nothing to hold, and
# stops climbing once it is back on flat ground or on top.
func climb_stick(delta: float) -> void:
	var r := body_radius * size
	var from := global_position + up * (0.8 * maxf(size, 1.0))
	var hit: Dictionary = call("cast", from, from + forward * (r + 0.6))
	if hit.is_empty():
		hit = call("cast", global_position + up * 1.2, global_position - up * 2.0)
	if hit.is_empty():
		var o := global_position + forward * 0.9 - up * 0.9
		hit = call("cast", o, o - forward * 1.5)
	if hit.is_empty():
		climbing = false   # nothing to hold: it falls
		return
	var n: Vector3 = hit["normal"]
	fall_speed = 0.0
	up = up.slerp(n, minf(1.0, 10.0 * delta)).normalized()
	global_position = global_position.lerp(hit["position"], minf(1.0, 18.0 * delta))
	if n.y > 0.8:
		climbing = false   # back on flat ground (or the top): the normal ground logic takes over
		return
	var f := forward - up * forward.dot(up)
	if f.length() < 0.01:
		f = up.cross(Vector3.RIGHT)
		if f.length() < 0.01:
			f = Vector3.FORWARD
	global_transform.basis = Basis.looking_at(f.normalized(), up)

# ---------- Smooth movement ----------
# Creatures speed up and slow down instead of snapping to full speed, and keep gliding a moment
# after they stop. walk_toward sets cur_speed; ease_stop runs on frames when nothing moved them.

var cur_speed := 0.0
var last_dir := Vector3.ZERO

func ease_stop(delta: float) -> void:
	if moving_now():
		return
	if cur_speed <= 0.05:
		cur_speed = 0.0
		return
	cur_speed = move_toward(cur_speed, 0.0, maxf(cur_speed, 4.0) * 4.0 * delta)
	if call("blocked", last_dir, cur_speed * delta + 0.5, true):
		cur_speed = 0.0
		return
	global_position += last_dir * cur_speed * delta
	if cur_speed > 0.8:
		set("moving", true)   # legs keep going while it glides to a stop

func moving_now() -> bool:
	return bool(get("moving"))

# ---------- Segmented bodies ----------
# Long bodies (centipede, worm) follow the exact path the head took, like a snake, instead of
# swinging out as a rigid line. That keeps the tail out of trees the head went around.

var uses_trail := false
var trail: Array = []        # where the head has been, newest first

func update_trail() -> void:
	var fwd := Vector3.FORWARD
	var f = get("forward")
	if f is Vector3:
		fwd = f
	if trail.is_empty():
		for k in 80:
			trail.append(global_position - fwd * (float(k) * 0.3))
		return
	if global_position.distance_to(trail[0]) > 0.3:
		trail.push_front(global_position)
		if trail.size() > 300:
			trail.resize(300)

# Places each segment (a dictionary with "node" and "z") on the trail, the right distance behind the head.
func follow_trail(body: Node3D, segs: Array, head_z: float, lift: float) -> void:
	var pts: Array = [global_position]
	pts.append_array(trail)
	var d := 0.0
	var k := 0
	var prev_local := body.to_local(global_position) + Vector3(0, lift, 0)
	for i in segs.size():
		var s: Dictionary = segs[i]
		var want := (float(s["z"]) - head_z) * size
		var seg_len := 0.0
		while k < pts.size() - 1:
			seg_len = (pts[k] as Vector3).distance_to(pts[k + 1])
			if d + seg_len >= want:
				break
			d += seg_len
			k += 1
		var p: Vector3 = pts[pts.size() - 1]
		if k < pts.size() - 1:
			p = (pts[k] as Vector3).lerp(pts[k + 1], (want - d) / maxf(seg_len, 0.0001))
		var local := body.to_local(p) + Vector3(0, lift, 0)
		var node: Node3D = s["node"]
		node.position = local
		var dir := prev_local - local
		if Vector2(dir.x, dir.z).length() > 0.01:
			node.rotation.y = atan2(-dir.x, -dir.z)
		prev_local = local
