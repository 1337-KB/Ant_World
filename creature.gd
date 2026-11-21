class_name Creature
extends Node3D

# The base for every creature (firefly, spider, beetle...). It holds what they all share:
# health, taking damage, dying, and dropping loot. Each animal extends this and adds its own
# behavior in _physics_process, usually as a small state machine.

signal died(creature: Creature)

var max_health := 30.0
var health := 30.0
var nocturnal := false      # true for creatures that only come out at night
var active := true          # inactive creatures are hidden and cannot be hit (fireflies by day)
var home := Vector3.ZERO     # where it lives; wandering stays near here
var is_loaded: Callable      # (position) -> true when the ground there exists. Set by main.
var ant: Ant                 # the player, set when it is spawned
var ground_at: Callable      # (x, z) -> ground height, set when it is spawned

func _ready() -> void:
	add_to_group("creatures")
	health = max_health

func set_active(value: bool) -> void:
	active = value
	visible = value

func take_damage(amount: float) -> void:
	health -= amount
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
