class_name Registry
extends RefCounted

# One central list of the things many systems need to look through: creatures, pickups, fires,
# traps, containers, placeables, pieces and landed rocks. Before, each system asked the whole
# scene tree "give me everything in group X" every time. Now each object signs itself in once
# when it is created and is removed automatically when it leaves the world, and everyone reads
# the same ready-made list.
#
# Use:  Registry.add(self, "creatures")      when the object is created
#       for c in Registry.of("creatures"):   to look through them
# Removal is automatic (it hooks the node's tree_exiting signal).

static var sets: Dictionary = {}

static func add(node: Node, kind: String) -> void:
	if not sets.has(kind):
		sets[kind] = {}
	var bucket: Dictionary = sets[kind]
	if bucket.has(node):
		return
	bucket[node] = true
	node.tree_exiting.connect(Registry.remove.bind(node, kind), CONNECT_ONE_SHOT)

static func remove(node: Node, kind: String) -> void:
	if sets.has(kind):
		var bucket: Dictionary = sets[kind]
		bucket.erase(node)

static func of(kind: String) -> Array:
	if not sets.has(kind):
		return []
	var bucket: Dictionary = sets[kind]
	return bucket.keys()

static func count(kind: String) -> int:
	if not sets.has(kind):
		return 0
	var bucket: Dictionary = sets[kind]
	return bucket.size()

static func clear_all() -> void:
	sets.clear()
