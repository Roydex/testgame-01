class_name TeamRules
extends RefCounted
## Minimal hostility interface for this phase. MatchRules (phase 4/5) will
## replace the internals; callers already go through these functions so no
## targeting / weapon code hard-codes team logic.

static func get_team(node: Node) -> int:
	if node == null:
		return -1
	var t: Variant = node.get(&"team_id")
	return int(t) if t != null else -1


static func is_hostile(a: Node, b: Node) -> bool:
	if a == null or b == null or a == b:
		return false
	return get_team(a) != get_team(b)


## Damage permission. Prototype rule: hostile and alive. MatchRules
## (phase 4/5) will extend this (friendly fire, mode rules) behind the same call.
static func can_damage(attacker: Node, victim: Node) -> bool:
	return is_hostile(attacker, victim) and is_alive(victim)


static func is_alive(node: Node) -> bool:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return false
	if node.has_method(&"is_alive"):
		return node.call(&"is_alive")
	return true


static func get_valid_targets(actor: Node, group: StringName = &"lock_targets") -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in actor.get_tree().get_nodes_in_group(group):
		var n3 := n as Node3D
		if n3 and is_alive(n3) and is_hostile(actor, n3):
			out.append(n3)
	return out
