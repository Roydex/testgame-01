class_name Grapple
extends Node3D
## HELLFANG 磁索钩爪. A hook that flies straight (travel time, no homing,
## sidestep to dodge) and stops on cover. A GRAB hit (unparryable,
## unguardable) either pulls the owner in (grounded target) or drags an
## airborne target down. The target is interrupted and stays staggered until
## the owner arrives (stagger = expected pull time + tail). Both use MovementModifier motion correction; this
## node never writes a mech's velocity. A miss costs extra recovery.

const MOD_PULL := &"grapple_pull"
const MOD_DRAG := &"grapple_drag"

var combat: CombatStateMachine
var owner_mech: MechMotor
var attack: AttackDefinition
var spec: GrappleSpec
var dir := Vector3.FORWARD
var travelled := 0.0
var _state := 0  # 0 flying, 1 pulling owner, 2 dragging target, 3 done
var _victim: MechMotor
var _t := 0.0
var _mod: MovementModifier
## Who carries _mod (always removed in _finish, even if the owner dies).
var _mod_on: MechMotor
var _line: MeshInstance3D
var _head: MeshInstance3D
var _shape: SphereShape3D


func launch(p_combat: CombatStateMachine, def: AttackDefinition, origin: Vector3, aim_dir: Vector3) -> void:
	combat = p_combat
	owner_mech = p_combat.motor
	attack = def
	spec = def.grapple_spec if def.grapple_spec else GrappleSpec.new()
	dir = aim_dir.normalized()
	global_position = origin
	name = "Grapple"
	_shape = SphereShape3D.new()
	_shape.radius = spec.radius
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.35, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.1)
	mat.emission_energy_multiplier = 3.0
	_head = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 0.6, 0.9)
	_head.mesh = bm
	_head.material_override = mat
	add_child(_head)
	_line = MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.08, 0.08, 1.0)
	_line.mesh = cm
	_line.material_override = mat
	_line.top_level = true
	add_child(_line)
	CombatEvents.entity_spawned.emit(self, &"grapple")


func _physics_process(delta: float) -> void:
	if owner_mech == null or not is_instance_valid(owner_mech) or not TeamRules.is_alive(owner_mech):
		_finish()
		return
	if _state == 1 and combat.state == CombatStateMachine.CombatState.STAGGER:
		_finish()  # owner got hit out of the pull
		return
	if owner_mech.in_hitstop():
		return
	match _state:
		0:
			_fly(delta)
		1:
			_pull_owner(delta)
		2:
			_drag_target(delta)
	_update_line()


func _fly(delta: float) -> void:
	var step := spec.speed * delta
	var from := global_position
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape
	q.transform = Transform3D(Basis(), from)
	q.motion = dir * step
	q.collision_mask = CombatTypes.WORLD_LAYER | CombatTypes.HURTBOX_LAYER
	q.collide_with_areas = true
	var ex: Array[RID] = [owner_mech.get_rid()]
	if combat.hurtbox:
		ex.append(combat.hurtbox.get_rid())
	q.exclude = ex
	for attempt in 4:
		var frac := space.cast_motion(q)
		if frac.is_empty() or frac[1] >= 1.0:
			break
		var at := from + dir * step * frac[1]
		var cq := PhysicsShapeQueryParameters3D.new()
		cq.shape = _shape
		cq.transform = Transform3D(Basis(), at)
		cq.collision_mask = q.collision_mask
		cq.collide_with_areas = true
		cq.exclude = q.exclude
		var hb: Hurtbox = null
		for t in space.intersect_shape(cq, 6):
			if t.collider is Hurtbox:
				hb = t.collider as Hurtbox
				break
		if hb == null:
			global_position = at
			_miss()  # cover / ground
			return
		if not (hb.mech is MechMotor) or not TeamRules.can_damage(owner_mech, hb.mech):
			ex.append(hb.get_rid())  # allies and non-mechs are passed through
			q.exclude = ex
			continue
		global_position = at
		_grab(hb.mech as MechMotor)
		return
	global_position = from + dir * step
	travelled += step
	if travelled >= spec.max_range:
		_miss()


func _grab(victim: MechMotor) -> void:
	var hit := HitInfo.new()
	hit.attacker = owner_mech
	hit.victim = victim
	hit.attack = attack
	hit.source_entity = self
	hit.source_position = global_position
	hit.hit_position = global_position
	hit.direction = dir
	var res := DamageSystem.resolve(hit)
	if res != CombatTypes.HitResult.HIT:
		_miss()  # evaded (i-frames) / not allowed
		return
	_victim = victim
	combat.report_delivery(attack, true)
	var vc := DamageSystem.get_combat(victim)
	var airborne := victim.is_air_state() and victim.get_height_above_ground(50.0) > spec.airborne_height
	if vc:
		vc.interrupt()  # always breaks charge / windup / deploy / guard
		vc.apply_stagger(grab_stagger_for(victim, airborne))
	_t = 0.0
	if airborne:
		_state = 2
		_mod = MovementModifier.create(MOD_DRAG)
		_mod.forced = true
		_mod.block_thrust = true
		_mod.forced_velocity = Vector3.DOWN * spec.drag_down_speed
		victim.add_modifier(_mod)
		_mod_on = victim
		CombatEvents.kit_event.emit(owner_mech, &"grapple_drag")
	else:
		_state = 1
		_mod = MovementModifier.create(MOD_PULL)
		_mod.forced = true
		owner_mech.add_modifier(_mod)
		_mod_on = owner_mech
		CombatEvents.kit_event.emit(owner_mech, &"grapple_pull")


## Stagger long enough to cover the pull (or drag) plus a short tail.
func grab_stagger_for(victim: MechMotor, airborne: bool) -> float:
	var travel := spec.drag_down_time
	if not airborne:
		var to := victim.global_position - owner_mech.global_position
		var flat := maxf(Vector3(to.x, 0.0, to.z).length() - spec.pull_stop_distance, 0.0)
		travel = minf(flat / maxf(spec.pull_self_speed, 0.1), spec.pull_max_time)
	return clampf(travel + spec.grab_stagger_tail, spec.grab_stagger, spec.grab_stagger_max)


func _pull_owner(delta: float) -> void:
	_t += delta
	if _victim == null or not is_instance_valid(_victim) or not TeamRules.is_alive(_victim):
		_end_pull(owner_mech)
		return
	global_position = _victim.get_lock_point()
	var to := _victim.global_position - owner_mech.global_position
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() <= spec.pull_stop_distance or _t >= spec.pull_max_time or (owner_mech.is_on_wall() and _t > 0.1):
		_end_pull(owner_mech)
		return
	var v := to.normalized() * spec.pull_self_speed
	v.y = clampf(v.y, -spec.pull_self_speed * 0.5, spec.pull_self_speed * 0.5)
	_mod.forced_velocity = v
	owner_mech.refresh_modifiers()


func _drag_target(delta: float) -> void:
	_t += delta
	if _victim == null or not is_instance_valid(_victim):
		_finish()
		return
	global_position = _victim.get_lock_point()
	if _t >= spec.drag_down_time or _victim.is_grounded_state():
		_end_pull(_victim)


func _end_pull(_m: MechMotor) -> void:
	_finish()


func _miss() -> void:
	combat.report_delivery(attack, false, spec.miss_recovery)
	CombatEvents.kit_event.emit(owner_mech, &"grapple_miss")
	_finish()


func _finish() -> void:
	if _state == 3:
		return
	_state = 3
	if _mod and _mod_on and is_instance_valid(_mod_on):
		# bleed off over a few ticks (the motor expires it): no slide-through
		_mod.forced_velocity = _mod.forced_velocity.normalized() * 3.0
		_mod.duration = 0.05
		_mod_on.refresh_modifiers()
	_mod_on = null
	CombatEvents.entity_removed.emit(self, &"grapple", false)
	queue_free()


func _update_line() -> void:
	if _line == null or owner_mech == null or not is_instance_valid(owner_mech):
		return
	var a := owner_mech.global_position + Vector3.UP * 2.6
	var b := global_position
	var len := a.distance_to(b)
	if len < 0.05:
		_line.visible = false
		return
	_line.visible = true
	_line.global_transform = Transform3D(Basis.looking_at(b - a, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT), (a + b) * 0.5)
	_line.scale = Vector3(1, 1, len)
