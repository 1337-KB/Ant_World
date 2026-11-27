class_name Cabin
extends RefCounted

# A log cabin in a forest clearing: stacked logs, a slate roof with moss, a stone chimney that
# smokes, glowing windows, a porch and steps, with a hearth, table and bed inside. It is a huge
# landmark for an ant, and the door stands open so you can walk in.
#
# Everything solid is drawn as one mesh (colours baked into the vertices) so the cabin costs a few
# draw calls, and it has real collision, so you can climb its walls and walk on the roof.
# Local frame: x across the front, z toward the door (front is +z), y up. y = 0 is the floor.

const W := 26.0            # width, side to side
const D := 20.0            # depth, front to back
const WALL_H := 9.0
const RISE := 8.0          # height of the roof above the walls
const R := 0.5             # log radius
const DOOR_HALF := 2.4
const DOOR_H := 6.0


# Procedural surface for the whole cabin: grain and knots in the wood, speckle and cracks in the
# stone, weathered slate, moss creeping up from the ground, and a bump so light catches the detail.
# It reads the colours the builder painted (warm = wood, grey = stone, blue-grey = slate) and
# works out the surface from that, so one material covers the whole building.
const SURFACE_SHADER := """
shader_type spatial;

varying vec3 op;
varying vec3 on;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x),
	               mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
	               mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += vnoise(p) * a;
		p = p * 2.03 + vec3(11.7, 3.1, 7.3);
		a *= 0.5;
	}
	return s;
}

// The surface height used for both the colour pattern and the bump.
float height_of(vec3 p, float kind) {
	if (kind < 0.5) {
		// Wood: grain running along the log, with a few knots.
		vec3 an = abs(on);
		float along_x = an.z + an.y;   // faces whose log runs along X
		vec3 q = mix(vec3(p.x * 0.18, p.y * 5.0, p.z * 5.0), vec3(p.x * 5.0, p.y * 5.0, p.z * 0.18), step(along_x, an.x));
		float g = fbm(q + fbm(q * 0.7) * 1.6);
		float rings = sin((g * 9.0 + p.y * 1.3) * 3.14159) * 0.5 + 0.5;
		float knot = smoothstep(0.78, 0.9, vnoise(p * 0.9));
		return g * 0.6 + rings * 0.25 + knot * 0.4;
	} else if (kind < 1.5) {
		// Stone: lumpy with fine speckle and dark cracks.
		float lump = fbm(p * 1.4);
		float speck = vnoise(p * 9.0);
		float crack = smoothstep(0.02, 0.0, abs(fbm(p * 2.2) - 0.5) - 0.012);
		return lump * 0.7 + speck * 0.2 - crack * 0.5;
	}
	// Slate: layered flaking and thin scratches.
	float flake = fbm(vec3(p.x * 1.2, p.y * 1.2, p.z * 1.2));
	float scratch = vnoise(vec3(p.x * 14.0, p.y * 2.0, p.z * 14.0));
	return flake * 0.7 + scratch * 0.2;
}

void vertex() {
	op = VERTEX;
	on = NORMAL;
}

void fragment() {
	vec3 base = COLOR.rgb;
	float mx = max(base.r, max(base.g, base.b));
	float mn = min(base.r, min(base.g, base.b));
	float sat = (mx - mn) / max(mx, 0.001);
	float kind = 1.0;                       // stone by default
	if (sat > 0.3 && base.r > base.b * 1.4) kind = 0.0;      // warm and saturated: wood
	else if (base.b > base.r * 1.05 && mx < 0.4) kind = 2.0; // cool and dark: slate
	if (base.g > base.r * 1.05 && base.g > base.b * 1.3) kind = 3.0;   // already green: moss, leave it

	float h = height_of(op, kind);
	float e = 0.06;
	float hx = height_of(op + vec3(e, 0.0, 0.0), kind) - h;
	float hy = height_of(op + vec3(0.0, e, 0.0), kind) - h;
	float hz = height_of(op + vec3(0.0, 0.0, e), kind) - h;
	vec3 grad = vec3(hx, hy, hz) / e;
	float bump = kind < 0.5 ? 0.35 : (kind < 1.5 ? 0.55 : 0.4);
	if (kind > 2.5) bump = 0.15;
	vec3 view_grad = (VIEW_MATRIX * MODEL_MATRIX * vec4(grad, 0.0)).xyz;
	NORMAL = normalize(NORMAL - view_grad * bump);

	vec3 col = base;
	float rough = 0.9;
	if (kind < 0.5) {
		col *= 0.72 + h * 0.55;
		col = mix(col, col * vec3(0.8, 0.75, 0.7), smoothstep(0.55, 0.9, fbm(op * 0.5)) * 0.5);   // sun-bleached patches
		rough = 0.8 + h * 0.15;
	} else if (kind < 1.5) {
		col *= 0.6 + h * 0.75;
		float tint = vnoise(op * 0.35);
		col = mix(col, col * vec3(1.12, 0.98, 0.82), tint * 0.6);                                  // rusty and cool stones
		rough = 0.92;
	} else if (kind < 2.5) {
		col *= 0.65 + h * 0.8;
		col += vec3(0.02, 0.03, 0.05) * smoothstep(0.55, 0.9, h);
		rough = 0.55 + (1.0 - h) * 0.3;                                                           // slightly glossy where it is worn
	}

	// Moss creeping up from the ground, and on the north-facing roof and stone tops.
	float low = 1.0 - smoothstep(0.0, 2.6, op.y + 0.6);
	float up = clamp(on.y, 0.0, 1.0);
	float moss_n = fbm(op * vec3(1.6, 2.4, 1.6));
	float moss = clamp((low * 0.9 + up * 0.18) * smoothstep(0.38, 0.72, moss_n + low * 0.25), 0.0, 1.0);
	if (kind > 2.5) moss = 0.0;
	col = mix(col, vec3(0.2, 0.3, 0.1) * (0.7 + moss_n * 0.7), moss * 0.75);
	rough = mix(rough, 1.0, moss);

	// Dirt and damp near the ground, a soft darkening in the crevices.
	col *= mix(1.0, 0.62, low * 0.55);
	col *= 0.9 + h * 0.2;

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.3, 1.0);
	SPECULAR = 0.25;
}
"""

const GLASS_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;

varying vec3 op;

void vertex() {
	op = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// A warm glow that wavers a little like lamplight, with a hint of uneven old glass.
	float t = TIME;
	float flick = 0.88 + 0.08 * sin(t * 7.3 + op.x) + 0.05 * sin(t * 13.1 + op.z * 1.7);
	float swirl = 0.5 + 0.5 * sin(op.y * 3.0 + op.x * 1.3 + t * 0.6);
	vec3 warm = mix(vec3(1.0, 0.62, 0.25), vec3(1.0, 0.8, 0.45), swirl * 0.5);
	ALBEDO = warm * flick;
}
"""

static var surface_shader: Shader
static var glass_shader: Shader

static func surface_material() -> ShaderMaterial:
	if surface_shader == null:
		surface_shader = Shader.new()
		surface_shader.code = SURFACE_SHADER
	var m := ShaderMaterial.new()
	m.shader = surface_shader
	return m

static func glass_material() -> ShaderMaterial:
	if glass_shader == null:
		glass_shader = Shader.new()
		glass_shader.code = GLASS_SHADER
	var m := ShaderMaterial.new()
	m.shader = glass_shader
	return m

static func wood(rng: RandomNumberGenerator, base: Color = Color(0.42, 0.27, 0.14)) -> Color:
	var k := rng.randf_range(0.82, 1.15)
	return Color(base.r * k, base.g * k, base.b * k)

static func box(b: Flora.Builder, size: Vector3, pos: Vector3, color: Color, rot: Basis = Basis.IDENTITY) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	b.add(bm, Transform3D(rot, pos), color)

static func box_xf(b: Flora.Builder, size: Vector3, xf: Transform3D, color: Color) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	b.add(bm, xf, color)

# A log lying along x.
static func log_x(b: Flora.Builder, length: float, pos: Vector3, color: Color) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = R
	cm.bottom_radius = R
	cm.height = length
	cm.radial_segments = 8
	cm.rings = 1
	b.add(cm, Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), pos), color)

# A log lying along z.
static func log_z(b: Flora.Builder, length: float, pos: Vector3, color: Color) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = R
	cm.bottom_radius = R
	cm.height = length
	cm.radial_segments = 8
	cm.rings = 1
	b.add(cm, Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), pos), color)

static func ball(b: Flora.Builder, r: float, pos: Vector3, scale: Vector3, color: Color) -> void:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	b.add(sm, Transform3D(Basis.from_scale(scale), pos), color)

static func col(body: StaticBody3D, size: Vector3, pos: Vector3, rot: Basis = Basis.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(rot, pos)
	body.add_child(cs)

# Where a point in the cabin's frame is in the world.
static func to_world(site: Dictionary, lx: float, lz: float) -> Vector2:
	var yaw: float = site["yaw"]
	return Vector2(float(site["x"]) + lx * cos(yaw) + lz * sin(yaw), float(site["z"]) - lx * sin(yaw) + lz * cos(yaw))

static func build(c: Content, site: Dictionary) -> void:
	var terrain: Terrain = c.terrain
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(int(site["x"]), int(site["z"])))
	var cx: float = site["x"]
	var cz: float = site["z"]
	var yaw: float = site["yaw"]

	# The floor sits just above the highest ground under the footprint; the foundation reaches down to meet the rest.
	var gy := -1000.0
	for lx: float in [-14.0, -7.0, 0.0, 7.0, 14.0]:
		for lz: float in [-11.0, -4.0, 4.0, 11.0, 17.0]:
			var wp := to_world(site, lx, lz)
			gy = maxf(gy, terrain.ground_height(wp.x, wp.y))
	gy += 0.5

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	c.m.stream.region_node(c.m.stream.region_key(cx, cz)).add_child(body)
	body.global_position = Vector3(cx, gy, cz)
	body.rotation.y = yaw
	body.set_meta("climbable", true)

	var b := Flora.Builder.new()   # the solid wood and stone
	var g := Flora.Builder.new()   # glowing window glass

	var slate := Color(0.22, 0.24, 0.27)
	var slate_dark := Color(0.15, 0.17, 0.2)
	var trim := Color(0.62, 0.34, 0.13)
	var plank := Color(0.46, 0.31, 0.17)
	var dark_wood := Color(0.2, 0.13, 0.08)

	# ---------- Foundation and floor ----------
	box(b, Vector3(W + 2.4, 9.0, D + 2.4), Vector3(0, -4.9, 0), Color(0.36, 0.35, 0.33))
	for i in 22:
		var t := float(i) / 22.0 * 4.0
		var side := int(t)
		var u := (t - float(side)) * 2.0 - 1.0
		var pos := Vector3.ZERO
		match side:
			0: pos = Vector3(u * (W * 0.5 + 1.2), 0.0, D * 0.5 + 1.2)
			1: pos = Vector3(W * 0.5 + 1.2, 0.0, u * (D * 0.5 + 1.2))
			2: pos = Vector3(-u * (W * 0.5 + 1.2), 0.0, -(D * 0.5 + 1.2))
			_: pos = Vector3(-(W * 0.5 + 1.2), 0.0, -u * (D * 0.5 + 1.2))
		var gray := rng.randf_range(0.38, 0.55)
		ball(b, 1.0, pos + Vector3(rng.randf_range(-0.3, 0.3), -0.4, rng.randf_range(-0.3, 0.3)), Vector3(rng.randf_range(1.2, 1.9), rng.randf_range(0.7, 1.1), rng.randf_range(1.0, 1.6)), Color(gray, gray * 0.97, gray * 0.92))
	box(b, Vector3(W - 0.2, 0.5, D - 0.2), Vector3(0, -0.25, 0), Color(0.36, 0.24, 0.13))
	col(body, Vector3(W + 2.4, 9.0, D + 2.4), Vector3(0, -4.9, 0))
	col(body, Vector3(W + 1.0, 1.4, D + 1.0), Vector3(0, -0.7, 0))

	# ---------- Log walls ----------
	var rows := int(WALL_H)
	for i in rows:
		var y := R + float(i)
		var long_fb := i % 2 == 0   # the corners lock together: the logs take turns reaching past the corner
		var fb_len := W + 1.6 if long_fb else W - 1.0
		var side_len := D - 1.0 if long_fb else D + 1.6
		var cw := wood(rng)
		log_x(b, fb_len, Vector3(0, y, -D * 0.5), cw)                       # back
		if y + R <= DOOR_H + 0.01:
			var seg := fb_len * 0.5 - DOOR_HALF
			log_x(b, seg, Vector3(-(DOOR_HALF + seg * 0.5), y, D * 0.5), wood(rng))
			log_x(b, seg, Vector3(DOOR_HALF + seg * 0.5, y, D * 0.5), wood(rng))
		else:
			log_x(b, fb_len, Vector3(0, y, D * 0.5), wood(rng))
		log_z(b, side_len, Vector3(-W * 0.5, y, 0), wood(rng))
		log_z(b, side_len, Vector3(W * 0.5, y, 0), wood(rng))
	col(body, Vector3(W + 2.0, WALL_H + 1.0, 2.0), Vector3(0, WALL_H * 0.5 + 0.5, -D * 0.5))
	col(body, Vector3(2.0, WALL_H + 1.0, D + 2.0), Vector3(-W * 0.5, WALL_H * 0.5 + 0.5, 0))
	col(body, Vector3(2.0, WALL_H + 1.0, D + 2.0), Vector3(W * 0.5, WALL_H * 0.5 + 0.5, 0))
	var front_seg := (W + 1.6) * 0.5 - DOOR_HALF
	col(body, Vector3(front_seg, WALL_H + 1.0, 2.0), Vector3(-(DOOR_HALF + front_seg * 0.5), WALL_H * 0.5 + 0.5, D * 0.5))
	col(body, Vector3(front_seg, WALL_H + 1.0, 2.0), Vector3(DOOR_HALF + front_seg * 0.5, WALL_H * 0.5 + 0.5, D * 0.5))
	col(body, Vector3(DOOR_HALF * 2.0 + 1.0, WALL_H - DOOR_H + 1.0, 2.0), Vector3(0, (WALL_H + DOOR_H) * 0.5 + 0.5, D * 0.5))
	# Solid gable ends, built as stacked blocks that follow the triangle, so nothing is hollow up there.
	for gi2 in 4:
		var gk := float(gi2)
		var gw := (W + 0.8) * (1.0 - (gk + 0.5) / 4.0)
		for gz: float in [-1.0, 1.0]:
			col(body, Vector3(gw, RISE / 4.0 + 0.2, 1.6), Vector3(0, WALL_H + RISE * (gk + 0.5) / 4.0, gz * D * 0.5))

	# Door frame and an open door.
	box(b, Vector3(0.55, DOOR_H + 0.4, 0.9), Vector3(-DOOR_HALF - 0.2, (DOOR_H + 0.4) * 0.5, D * 0.5 + 0.15), dark_wood)
	box(b, Vector3(0.55, DOOR_H + 0.4, 0.9), Vector3(DOOR_HALF + 0.2, (DOOR_H + 0.4) * 0.5, D * 0.5 + 0.15), dark_wood)
	box(b, Vector3(DOOR_HALF * 2.0 + 1.2, 0.6, 0.9), Vector3(0, DOOR_H + 0.2, D * 0.5 + 0.15), dark_wood)
	var hinge := Transform3D(Basis(Vector3.UP, -1.3), Vector3(-DOOR_HALF + 0.1, 0.0, D * 0.5 + 0.5))
	box_xf(b, Vector3(DOOR_HALF - 0.2, DOOR_H - 0.2, 0.35), hinge * Transform3D(Basis.IDENTITY, Vector3(DOOR_HALF * 0.5, DOOR_H * 0.5, 0)), plank)
	box_xf(b, Vector3(DOOR_HALF - 0.2, 0.3, 0.45), hinge * Transform3D(Basis.IDENTITY, Vector3(DOOR_HALF * 0.5, 1.6, 0)), dark_wood)
	box_xf(b, Vector3(DOOR_HALF - 0.2, 0.3, 0.45), hinge * Transform3D(Basis.IDENTITY, Vector3(DOOR_HALF * 0.5, 4.6, 0)), dark_wood)

	# ---------- Windows (glass glows, frames and shutters are wood) ----------
	var panes: Array = [
		[Vector3(-7.6, 4.2, D * 0.5 + R + 0.05), Vector2(3.0, 3.4), 0.0],
		[Vector3(7.6, 4.2, D * 0.5 + R + 0.05), Vector2(3.0, 3.4), 0.0],
		[Vector3(0, WALL_H + 3.2, D * 0.5 + 0.55), Vector2(2.0, 2.8), 0.0],       # the little upper window in the gable
		[Vector3(-W * 0.5 - R - 0.05, 4.2, 1.5), Vector2(3.0, 3.4), PI * 0.5],
		[Vector3(0, 4.2, -D * 0.5 - R - 0.05), Vector2(3.0, 3.4), 0.0],
	]
	for p in panes:
		var pos: Vector3 = p[0]
		var sz: Vector2 = p[1]
		var rot := Basis(Vector3.UP, float(p[2]))
		box(g, Vector3(sz.x, sz.y, 0.12), pos, Color(1.0, 0.72, 0.33), rot)
		var fwd := rot * Vector3(0, 0, 0.1)
		box(b, Vector3(sz.x + 0.7, sz.y + 0.7, 0.2), pos - fwd * 1.0, dark_wood, rot)
		box(b, Vector3(0.18, sz.y, 0.2), pos + fwd * 1.2, dark_wood, rot)           # the bars across the glass
		box(b, Vector3(sz.x, 0.18, 0.2), pos + fwd * 1.2, dark_wood, rot)
	for sx: float in [-1.0, 1.0]:
		var shutter_x := 7.6 * sx
		box(b, Vector3(1.2, 3.6, 0.25), Vector3(shutter_x - 2.4, 4.2, D * 0.5 + R + 0.15), trim)
		box(b, Vector3(1.2, 3.6, 0.25), Vector3(shutter_x + 2.4, 4.2, D * 0.5 + R + 0.15), trim)

	# ---------- Gables and roof ----------
	var wall_top := WALL_H
	for sz: float in [-1.0, 1.0]:
		var pm := PrismMesh.new()
		pm.size = Vector3(W + 0.8, RISE, 0.9)
		pm.left_to_right = 0.5
		b.add(pm, Transform3D(Basis.IDENTITY, Vector3(0, wall_top + RISE * 0.5, sz * D * 0.5)), plank)
	var th := atan(RISE / (W * 0.5))
	var yr := wall_top + RISE + 0.45
	var slab_len := (W * 0.5) / cos(th) + 1.9
	var slab_w := D + 3.4
	for side: float in [-1.0, 1.0]:
		var down := Vector3(side * cos(th), -sin(th), 0)
		var center := Vector3(0, yr, 0) + down * (slab_len * 0.5 - 0.4)
		var rb := Basis(Vector3(0, 0, 1), -side * th)
		var xf := Transform3D(rb, center)
		box_xf(b, Vector3(slab_len, 0.8, slab_w), xf, slate)
		# Rows of shingles, a few mossy patches, and the bright trim boards on the gable edges.
		var u := -slab_len * 0.5 + 1.0
		while u < slab_len * 0.5:
			box_xf(b, Vector3(0.2, 0.16, slab_w), xf * Transform3D(Basis.IDENTITY, Vector3(u, 0.46, 0)), slate_dark)
			u += 1.3
		for k in 9:
			var mu := rng.randf_range(-slab_len * 0.42, slab_len * 0.42)
			var mw := rng.randf_range(-slab_w * 0.42, slab_w * 0.42)
			var ms := rng.randf_range(0.8, 1.9)
			b.add(_flat_sphere(), xf * Transform3D(Basis.from_scale(Vector3(ms * 1.5, 0.28, ms)), Vector3(mu, 0.5, mw)), Color(0.26, 0.38, 0.14))
		for sz2: float in [-1.0, 1.0]:
			box_xf(b, Vector3(slab_len + 0.2, 0.95, 0.4), xf * Transform3D(Basis.IDENTITY, Vector3(0, -0.1, sz2 * (slab_w * 0.5))), trim)
		col(body, Vector3(slab_len, 1.6, slab_w), center + rb * Vector3(0, -0.4, 0), rb)
	box(b, Vector3(1.3, 0.55, slab_w + 0.2), Vector3(0, yr + 0.55, 0), slate_dark)

	# ---------- Stone chimney ----------
	var ch_top := yr + 3.6
	var ch_pos := Vector3(W * 0.5 + 1.7, 0, -4.0)
	var ch_rows := int(ch_top + 1.0)
	for i in ch_rows:
		var y := -0.5 + float(i) + 0.5
		for sx2: float in [-1.0, 1.0]:
			for sz3: float in [-1.0, 1.0]:
				var s := rng.randf_range(0.42, 0.62)
				var sc := Color(s, s * 0.97, s * 0.9)
				if rng.randf() < 0.2:
					sc = Color(s * 1.1, s * 0.85, s * 0.7)   # the odd rusty stone
				box(b, Vector3(rng.randf_range(1.5, 1.85), 0.95, rng.randf_range(1.4, 1.75)), ch_pos + Vector3(sx2 * 0.85 + rng.randf_range(-0.1, 0.1), y, sz3 * 0.8 + rng.randf_range(-0.1, 0.1)), sc)
	box(b, Vector3(4.1, 0.5, 3.8), ch_pos + Vector3(0, ch_top + 0.3, 0), Color(0.3, 0.3, 0.3))
	col(body, Vector3(3.4, ch_top + 0.5, 3.2), ch_pos + Vector3(0, (ch_top - 0.5) * 0.5, 0))

	# ---------- Porch ----------
	box(b, Vector3(9.0, 0.5, 5.0), Vector3(0, -0.25, D * 0.5 + 2.6), Color(0.4, 0.27, 0.15))
	box(b, Vector3(8.6, 7.0, 4.6), Vector3(0, -4.0, D * 0.5 + 2.6), Color(0.34, 0.33, 0.31))
	box(b, Vector3(5.2, 4.0, 1.5), Vector3(0, -2.6, D * 0.5 + 5.9), Color(0.4, 0.38, 0.35))
	box(b, Vector3(5.2, 0.5, 1.5), Vector3(0, -0.8, D * 0.5 + 5.9), Color(0.42, 0.29, 0.16))
	col(body, Vector3(9.0, 0.5, 5.0), Vector3(0, -0.25, D * 0.5 + 2.6))
	col(body, Vector3(8.6, 7.0, 4.6), Vector3(0, -4.0, D * 0.5 + 2.6))
	col(body, Vector3(5.2, 4.8, 1.5), Vector3(0, -2.9, D * 0.5 + 5.9))
	for sx3: float in [-1.0, 1.0]:
		var post := CylinderMesh.new()
		post.top_radius = 0.3
		post.bottom_radius = 0.34
		post.height = 7.2
		post.radial_segments = 8
		b.add(post, Transform3D(Basis.IDENTITY, Vector3(sx3 * 4.0, 3.6, D * 0.5 + 4.8)), wood(rng, Color(0.36, 0.23, 0.12)))
	box(b, Vector3(8.8, 0.6, 0.7), Vector3(0, 7.2, D * 0.5 + 4.8), dark_wood)
	var porch_roof := Basis(Vector3(1, 0, 0), 0.14)
	box(b, Vector3(10.4, 0.5, 6.6), Vector3(0, 7.9, D * 0.5 + 2.5), slate, porch_roof)
	col(body, Vector3(10.4, 1.2, 6.6), Vector3(0, 7.6, D * 0.5 + 2.5), porch_roof)
	for sx4: float in [-1.0, 1.0]:
		col(body, Vector3(0.8, 7.4, 0.8), Vector3(sx4 * 4.0, 3.7, D * 0.5 + 4.8))

	# ---------- Inside: hearth, table, bed ----------
	box(b, Vector3(2.6, 4.8, 5.6), Vector3(W * 0.5 - 1.7, 2.4, -4.0), Color(0.47, 0.45, 0.42))
	box(b, Vector3(0.9, 2.6, 3.2), Vector3(W * 0.5 - 3.05, 1.5, -4.0), Color(0.05, 0.04, 0.04))
	box(g, Vector3(0.5, 0.9, 2.2), Vector3(W * 0.5 - 3.0, 0.6, -4.0), Color(1.0, 0.45, 0.12))
	col(body, Vector3(2.6, 4.8, 5.6), Vector3(W * 0.5 - 1.7, 2.4, -4.0))
	box(b, Vector3(5.6, 0.4, 3.4), Vector3(-3.0, 3.0, 3.0), plank)
	for lx2: float in [-1.0, 1.0]:
		for lz2: float in [-1.0, 1.0]:
			box(b, Vector3(0.45, 2.8, 0.45), Vector3(-3.0 + lx2 * 2.4, 1.4, 3.0 + lz2 * 1.4), dark_wood)
	col(body, Vector3(5.6, 3.0, 3.4), Vector3(-3.0, 1.5, 3.0))
	box(b, Vector3(7.0, 1.0, 3.8), Vector3(-W * 0.5 + 4.3, 0.5, -D * 0.5 + 2.4), dark_wood)
	box(b, Vector3(6.6, 0.7, 3.4), Vector3(-W * 0.5 + 4.3, 1.35, -D * 0.5 + 2.4), Color(0.85, 0.8, 0.68))
	box(b, Vector3(4.2, 0.8, 3.5), Vector3(-W * 0.5 + 5.6, 1.6, -D * 0.5 + 2.4), Color(0.5, 0.17, 0.12))
	box(b, Vector3(1.6, 0.6, 2.4), Vector3(-W * 0.5 + 1.6, 1.9, -D * 0.5 + 2.4), Color(0.9, 0.86, 0.75))
	col(body, Vector3(7.0, 1.9, 3.8), Vector3(-W * 0.5 + 4.3, 0.95, -D * 0.5 + 2.4))
	for i in 2:
		var stool := CylinderMesh.new()
		stool.top_radius = 0.9
		stool.bottom_radius = 0.8
		stool.height = 1.7
		stool.radial_segments = 8
		b.add(stool, Transform3D(Basis.IDENTITY, Vector3(-5.5 + float(i) * 5.5, 0.85, 5.8)), plank)
		col(body, Vector3(1.7, 1.7, 1.7), Vector3(-5.5 + float(i) * 5.5, 0.85, 5.8))

	# ---------- Outside: woodpile and a path of stepping stones ----------
	var pile_x := -W * 0.5 - 3.6
	box(b, Vector3(5.2, 6.0, 4.4), Vector3(pile_x, -3.0, 4.0), Color(0.33, 0.32, 0.3))
	for row in 4:
		var n := 5 - (row % 2)
		for k in n:
			log_z(b, 3.8, Vector3(pile_x + (float(k) - float(n - 1) * 0.5) * 0.95, 0.4 + float(row) * 0.8, 4.0), wood(rng, Color(0.5, 0.34, 0.2)))
	col(body, Vector3(5.2, 3.8, 4.4), Vector3(pile_x, 1.2, 4.0))
	for i in 9:
		var lz3 := D * 0.5 + 8.5 + float(i) * 2.6
		var lx3 := rng.randf_range(-0.9, 0.9) + sin(float(i) * 0.7) * 1.2
		var wp2 := to_world(site, lx3, lz3)
		var gh := terrain.ground_height(wp2.x, wp2.y)
		var stone := CylinderMesh.new()
		stone.top_radius = 1.1
		stone.bottom_radius = 1.3
		stone.height = 0.6
		stone.radial_segments = 7
		var sg := rng.randf_range(0.42, 0.55)
		b.add(stone, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(lx3, gh - gy + 0.05, lz3)), Color(sg, sg * 0.98, sg * 0.92))
		col(body, Vector3(2.0, 1.2, 2.0), Vector3(lx3, gh - gy + 0.05, lz3))

	# ---------- Build the meshes ----------
	var mi := MeshInstance3D.new()
	mi.mesh = b.build()
	mi.material_override = surface_material()
	c.fade_far(mi)
	body.add_child(mi)

	var gi := MeshInstance3D.new()
	gi.mesh = g.build()
	gi.material_override = glass_material()
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.fade_far(gi)
	body.add_child(gi)

	# ---------- Light and smoke ----------
	var room := OmniLight3D.new()
	room.light_color = Color(1.0, 0.68, 0.38)
	room.light_energy = 2.2
	room.omni_range = 26.0
	room.position = Vector3(0, 6.0, 1.0)
	body.add_child(room)
	var porch_light := OmniLight3D.new()
	porch_light.light_color = Color(1.0, 0.72, 0.4)
	porch_light.light_energy = 1.6
	porch_light.omni_range = 18.0
	porch_light.position = Vector3(0, 5.5, D * 0.5 + 6.0)
	body.add_child(porch_light)
	var lantern := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.35
	lm.height = 0.7
	lantern.mesh = lm
	var lantern_mat := StandardMaterial3D.new()
	lantern_mat.albedo_color = Color(1.0, 0.8, 0.45)
	lantern_mat.emission_enabled = true
	lantern_mat.emission = Color(1.0, 0.6, 0.2)
	lantern_mat.emission_energy_multiplier = 3.0
	lantern.material_override = lantern_mat
	lantern.position = Vector3(4.0, 5.9, D * 0.5 + 5.4)
	body.add_child(lantern)
	var hearth_light := OmniLight3D.new()
	hearth_light.light_color = Color(1.0, 0.5, 0.2)
	hearth_light.light_energy = 2.0
	hearth_light.omni_range = 14.0
	hearth_light.position = Vector3(W * 0.5 - 3.5, 1.8, -4.0)
	body.add_child(hearth_light)
	var flicker := hearth_light.create_tween().set_loops()
	flicker.tween_property(hearth_light, "light_energy", 2.7, 0.32).set_trans(Tween.TRANS_SINE)
	flicker.tween_property(hearth_light, "light_energy", 1.5, 0.41).set_trans(Tween.TRANS_SINE)
	flicker.tween_property(hearth_light, "light_energy", 2.3, 0.27).set_trans(Tween.TRANS_SINE)

	# Smoke curling out of the chimney and drifting with the wind.
	var smoke := Effects.make(36, 8.0, 3.6, false,
		[Color(0.88, 0.88, 0.88, 0.0), Color(0.88, 0.88, 0.88, 0.32), Color(0.82, 0.82, 0.84, 0.0)], [0.5, 1.2, 2.6])
	smoke.direction = Vector3.UP
	smoke.spread = 7.0
	smoke.initial_velocity_min = 2.4
	smoke.initial_velocity_max = 3.4
	smoke.gravity = Vector3(0.45, 0.5, 0.3)
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.7
	smoke.emitting = true
	body.add_child(smoke)
	smoke.position = ch_pos + Vector3(0, ch_top + 0.6, 0)

	# A ring of bushes at the edge of the yard, so the cabin sits in the trees.
	for i in 16:
		var a := TAU * float(i) / 16.0 + rng.randf_range(-0.15, 0.15)
		var lx4 := cos(a) * (W * 0.5 + 8.0 + rng.randf_range(0.0, 4.0))
		var lz4 := sin(a) * (D * 0.5 + 8.0 + rng.randf_range(0.0, 4.0)) + 2.0
		var wp3 := to_world(site, lx4, lz4)
		c.add_shrub(wp3.x, wp3.y, rng)

static func _flat_sphere() -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	return sm
