class_name Look
extends RefCounted

# One place that decides how colourful the world is. Every plant, flower, tree and patch of ground
# passes its colour through mute(), which turns the bright "cartoon" palette into natural, earthy
# tones: less saturated, greens pulled toward olive. Change STRENGTH to dial it:
#   0.0 = the original bright cartoon colours, 1.0 = fully muted (default), 1.5 = very drab.
# The lighting also has a saturation setting (graphics.gd and atmosphere.gd).

const STRENGTH := 1.0
const SATURATION_KEPT := 0.58    # at STRENGTH 1.0, colours keep this share of their saturation
const GREEN_TO_OLIVE := 0.3      # how far green hues are pulled toward olive
const OLIVE_HUE := 0.2

static func mute(c: Color, amount: float = 1.0) -> Color:
	var k := STRENGTH * amount
	if k <= 0.0:
		return c
	var h := c.h
	var s := c.s
	var v := c.v
	if h > 0.16 and h < 0.48:
		h = lerpf(h, OLIVE_HUE, GREEN_TO_OLIVE * minf(k, 1.0))
	s *= lerpf(1.0, SATURATION_KEPT, minf(k, 1.5))
	v *= lerpf(1.0, 0.93, minf(k, 1.0))
	return Color.from_hsv(h, clampf(s, 0.0, 1.0), clampf(v, 0.0, 1.0), c.a)
