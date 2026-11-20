class_name TargetingSystem
extends Node
## Lock-on: acquire, cycle, and lose targets. Hostility always goes through
## TeamRules so no mode / team logic lives here.

signal target_changed(old_target: Node3D, new_target: Node3D, reason: String)

@export var lock_range: float = 150.0
@export var lose_range: float = 175.0
## Seconds a locked target may stay occluded before the lock drops.
@export var lose_los_time: float = 3.0
@export var los_mask: int = 1
## Auto-pick the next target when the current one is destroyed.
@export var auto_switch_on_destroy: bool = true

@export_group("Threat (Q acquire)")
## Acquire picks the lowest score = distance − threat (both in metres), so a
## nearby unit that is pressuring us wins over one we merely look at
## (playtest R2-3). The camera direction is only a small tie-breaker.
@export var threat_targeting_me: float = 12.0
@export var threat_attacking_me: float = 10.0
## Per point of damage it dealt us within `threat_memory` s (capped).
@export var threat_per_damage: float = 0.6
@export var threat_damage_cap: float = 20.0
@export var threat_memory: float = 5.0
@export var view_angle_weight: float = 0.03

var owner_mech: Node3D
var camera: Camera3D
var current: Node3D
var occluded_time: float = 0.0
var last_lost_reason: String = ""
var _clock := 0.0
## attacker instance id → [last time, damage within memory]
var _recent_damage: Dictionary = {}


func setup(p_owner: Node3D, p_camera: Camera3D) -> void:
	owner_mech = p_owner
	camera = p_camera
	if not CombatEvents.hit_resolved.is_connected(_on_hit):
		CombatEvents.hit_resolved.connect(_on_hit)


func _on_hit(h: HitInfo) -> void:
	if owner_mech == null or h.victim != owner_mech or h.attacker == null or h.final_damage <= 0.0:
		return
	var id := h.attacker.get_instance_id()
	var e: Array = _recent_damage.get(id, [_clock, 0.0])
	var amount: float = e[1] if _clock - float(e[0]) <= threat_memory else 0.0
	_recent_damage[id] = [_clock, amount + h.final_damage]


## How much `t` threatens us right now, in metres of distance it is worth.
func threat_of(t: Node3D) -> float:
	var th := 0.0
	var tc := DamageSystem.get_combat(t)
	var its_target: Variant = tc.aim_target if tc else t.get(&"target")
	if its_target == owner_mech:
		th += threat_targeting_me
		if tc and (tc.state == CombatStateMachine.CombatState.ATTACK or tc.state == CombatStateMachine.CombatState.CHARGE):
			th += threat_attacking_me
	var e: Array = _recent_damage.get(t.get_instance_id(), [])
	if not e.is_empty() and _clock - float(e[0]) <= threat_memory:
		th += minf(float(e[1]) * threat_per_damage, threat_damage_cap)
	return th


func has_target() -> bool:
	return current != null and is_instance_valid(current)


func get_target_point(t: Node3D = null) -> Vector3:
	if t == null:
		t = current
	if t.has_method(&"get_lock_point"):
		return t.call(&"get_lock_point")
	return t.global_position


func toggle_lock() -> void:
	if has_target():
		_set_target(null, "manual_release")
	else:
		acquire()


func acquire() -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var fwd := _view_forward()
	var origin := _view_origin()
	for t in _candidates():
		var to := get_target_point(t) - origin
		var dist := owner_mech.global_position.distance_to(get_target_point(t))
		var angle := rad_to_deg(fwd.angle_to(to))
		var score := dist - threat_of(t) + angle * view_angle_weight
		if score < best_score:
			best_score = score
			best = t
	_set_target(best, "acquire" if best else "none_available")
	return best


## dir = +1 next to the right, -1 next to the left (relative to camera).
func cycle(dir: int) -> void:
	var cands := _candidates()
	if cands.is_empty():
		return
	if not has_target():
		acquire()
		return
	var fwd := _view_forward()
	var origin := _view_origin()
	var scored: Array = []
	for t in cands:
		var to := get_target_point(t) - origin
		var a := Vector2(fwd.x, fwd.z).angle_to(Vector2(to.x, to.z))
		scored.append([a, t])
	scored.sort_custom(func(x, y): return x[0] < y[0])
	var idx := -1
	for i in scored.size():
		if scored[i][1] == current:
			idx = i
	if idx == -1:
		_set_target(scored[0][1], "cycle")
		return
	var n: int = scored.size()
	var next_idx := (idx + dir + n) % n
	if scored[next_idx][1] != current:
		_set_target(scored[next_idx][1], "cycle")


func _physics_process(delta: float) -> void:
	_clock += delta
	if current == null:
		return
	if not TeamRules.is_alive(current):
		var dead := current
		_set_target(null, "destroyed")
		if auto_switch_on_destroy:
			var nxt := _nearest(dead)
			if nxt:
				_set_target(nxt, "auto_switch")
		return
	var dist := owner_mech.global_position.distance_to(get_target_point())
	if dist > lose_range:
		_set_target(null, "out_of_range")
		return
	if _has_los(current):
		occluded_time = 0.0
	else:
		occluded_time += delta
		if occluded_time >= lose_los_time:
			_set_target(null, "occluded")


func _nearest(exclude: Node3D) -> Node3D:
	var best: Node3D = null
	var best_d := lock_range
	for t in _candidates():
		if t == exclude:
			continue
		var d := owner_mech.global_position.distance_to(get_target_point(t))
		if d < best_d:
			best_d = d
			best = t
	return best


func _candidates() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if owner_mech == null:
		return out
	for t in TeamRules.get_valid_targets(owner_mech):
		if owner_mech.global_position.distance_to(get_target_point(t)) <= lock_range:
			out.append(t)
	return out


func _has_los(t: Node3D) -> bool:
	var space := owner_mech.get_world_3d().direct_space_state
	var from := owner_mech.global_position + Vector3.UP * 3.0
	var q := PhysicsRayQueryParameters3D.create(from, get_target_point(t), los_mask)
	var excl: Array[RID] = []
	if owner_mech is CollisionObject3D:
		excl.append((owner_mech as CollisionObject3D).get_rid())
	q.exclude = excl
	var hit := space.intersect_ray(q)
	return hit.is_empty() or hit.collider == t


func _view_forward() -> Vector3:
	if camera:
		return -camera.global_basis.z
	return -owner_mech.global_basis.z


func _view_origin() -> Vector3:
	return camera.global_position if camera else owner_mech.global_position


func _set_target(t: Node3D, reason: String) -> void:
	if t == current:
		return
	var old := current
	current = t
	occluded_time = 0.0
	if t == null:
		last_lost_reason = reason
	target_changed.emit(old, t, reason)
