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

func hit_center() -> Vector3:
	return global_position + global_transform.basis * hit_offset

func _ready() -> void:
	add_to_group("creatures")
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
	show_bar()
	on_hurt()
	if health <= 0.0:
		die()

func on_hurt() -> void:
	pass   # animals override this to flash, flee, or get angry

func die() -> void:
	died.emit(self)
	queue_free()

# What this creature drops when it dies ("" for nothing).
func loot_kind() -> String:
	return ""
