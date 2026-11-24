class_name Chunk
extends RefCounted

const SIZE := 16

# Density: positive = solid, negative = air, 0 = exactly on the surface.
var density := PackedFloat32Array()
# Material ID (Blocks.STONE etc.) for each sample.
var material := PackedByteArray()

func _init() -> void:
	var count := SIZE * SIZE * SIZE
	density.resize(count)
	density.fill(-1.0)  # new chunks start as air
	material.resize(count)

static func in_bounds(x: int, y: int, z: int) -> bool:
	return x >= 0 and x < SIZE and y >= 0 and y < SIZE and z >= 0 and z < SIZE

func _index(x: int, y: int, z: int) -> int:
	return x + z * SIZE + y * SIZE * SIZE

func get_density(x: int, y: int, z: int) -> float:
	if not in_bounds(x, y, z):
		return -1.0
	return density[_index(x, y, z)]

func get_material(x: int, y: int, z: int) -> int:
	if not in_bounds(x, y, z):
		return Blocks.AIR
	return material[_index(x, y, z)]

func set_density(x: int, y: int, z: int, d: float) -> void:
	if in_bounds(x, y, z):
		density[_index(x, y, z)] = d

func set_voxel(x: int, y: int, z: int, d: float, mat: int) -> void:
	if in_bounds(x, y, z):
		var i := _index(x, y, z)
		density[i] = d
		material[i] = mat
