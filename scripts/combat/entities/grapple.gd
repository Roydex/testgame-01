class_name Grapple
extends Node3D
## HELLFANG 磁索钩爪. A claw on a chain, thrown from the power claw: it
## flies straight (travel time, no homing, sidestep to dodge), latches onto
## walls (pulls the owner there: mobility) and reels back on a miss. A GRAB hit (unparryable,
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
var _state := 0  # 0 flying, 1 pulling owner, 2 dragging target, 3 done, 4 wall pull, 5 reeling back
var _victim: MechMotor
var _t := 0.0
var _mod: MovementModifier
## Who carries _mod (always removed in _finish, even if the owner dies).
var _mod_on: MechMotor
var _chain: MultiMeshInstance3D
var _head: Node3D
var _prongs: Array[Node3D] = []
var _shape: SphereShape3D
var _anchor := Vector3.ZERO
const LINK := 0.45  # chain link spacing (m)


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
	_build_visual()
	_set_claw_launched(true)
	CombatEvents.entity_spawned.emit(self, &"grapple")


## Presentation: a three-pronged claw head and a chain of links back to the
## owner's power claw (the arm's claw is hidden while it is out).
func _build_visual() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.32, 0.3, 0.3)
	steel.metallic = 0.7
	steel.roughness = 0.35
	var hot := StandardMaterial3D.new()
	hot.albedo_color = Color(1.0, 0.4, 0.15)
	hot.emission_enabled = true
	hot.emission = Color(1.0, 0.35, 0.1)
	hot.emission_energy_multiplier = 3.0
	_head = Node3D.new()
	add_child(_head)
	var hub := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.55, 0.55, 0.5)
	hub.mesh = hm
	hub.material_override = steel
	_head.add_child(hub)
	var core := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.3, 0.3, 0.3)
	core.mesh = cm
	core.material_override = hot
	core.position = Vector3(0, 0, -0.2)
	_head.add_child(core)
	for i in 3:
		var pivot := Node3D.new()
		pivot.rotation.z = TAU * i / 3.0
		_head.add_child(pivot)
		var prong := Node3D.new()
		prong.position = Vector3(0, 0.25, -0.2)
		pivot.add_child(prong)
		var pm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, 0.14, 0.9)
		pm.mesh = bm
		pm.material_override = steel
		pm.position = Vector3(0, 0, -0.4)
		prong.add_child(pm)
		var tipm := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.12, 0.12, 0.25)
		tipm.mesh = tb
		tipm.material_override = hot
		tipm.position = Vector3(0, -0.12, -0.85)
		tipm.rotation.x = -0.6
		prong.add_child(tipm)
		prong.rotation.x = 0.55  # open while flying
		_prongs.append(prong)
	var link := BoxMesh.new()
	link.size = Vector3(0.16, 0.32, LINK * 0.9)
	var link_mat := steel.duplicate() as StandardMaterial3D
	link_mat.emission_enabled = true
	link_mat.emission = Color(1.0, 0.35, 0.1)
	link_mat.emission_energy_multiplier = 0.8  # magnetised chain: a faint furnace glow
	link.material = link_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = link
	mm.instance_count = int(ceil(spec.max_range * 1.4 / LINK)) + 2
	mm.visible_instance_count = 0
	_chain = MultiMeshInstance3D.new()
	_chain.multimesh = mm
	_chain.top_level = true
	_chain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_chain)


func _close_claw() -> void:
	for p in _prongs:
		p.rotation.x = -0.15


## The owner's visual hides its arm claw while the claw is out (duck-typed).
func _set_claw_launched(on: bool) -> void:
	var vis := owner_mech.get_node_or_null(^"Visual") if owner_mech and is_instance_valid(owner_mech) else null
	if vis and vis.has_method(&"set_claw_launched"):
		vis.call(&"set_claw_launched", on)


func _chain_start() -> Vector3:
	var vis := owner_mech.get_node_or_null(^"Visual")
	if vis and vis.has_method(&"grapple_anchor"):
		return vis.call(&"grapple_anchor")
	return owner_mech.global_position + Vector3.UP * 2.6


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
		4:
			_pull_to_wall(delta)
		5:
			_reel_back(delta)
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
			var rest := space.get_rest_info(cq)
			var n: Vector3 = rest.get("normal", Vector3.UP)
			if spec.wall_latch and absf(n.y) < spec.wall_max_normal_y:
				_latch_wall(at, n)
			else:
				_miss()  # floor / ceiling / nothing to bite
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
	_close_claw()
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


## 钩墙位移: the claw bites a wall; the owner is pulled to it (no damage).
func _latch_wall(at: Vector3, normal: Vector3) -> void:
	_close_claw()
	_anchor = at
	_t = 0.0
	combat.report_delivery(attack, true)
	combat.cap_cooldown(attack.id, spec.miss_cooldown)
	_state = 4
	_mod = MovementModifier.create(MOD_PULL)
	_mod.forced = true
	owner_mech.add_modifier(_mod)
	_mod_on = owner_mech
	look_at(at - normal, Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT)
	CombatEvents.kit_event.emit(owner_mech, &"grapple_wall")


func _pull_to_wall(delta: float) -> void:
	_t += delta
	var to := _anchor - (owner_mech.global_position + Vector3.UP * 2.0)
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() <= spec.wall_stop_distance or _t >= spec.wall_max_time or (owner_mech.is_on_wall() and _t > 0.1):
		_finish()
		return
	var v := to.normalized() * spec.wall_pull_speed
	v.y = clampf(v.y, -spec.wall_pull_speed * 0.5, spec.wall_pull_speed * 0.6)
	_mod.forced_velocity = v
	owner_mech.refresh_modifiers()


func _miss() -> void:
	combat.report_delivery(attack, false, spec.miss_recovery)
	combat.cap_cooldown(attack.id, spec.miss_cooldown)
	CombatEvents.kit_event.emit(owner_mech, &"grapple_miss")
	_state = 5  # reel the chain back in (visual only; the miss is already resolved)


func _reel_back(delta: float) -> void:
	var a := _chain_start()
	var to := a - global_position
	var step := spec.retract_speed * delta
	if to.length() <= step + 0.3:
		_finish()
		return
	global_position += to.normalized() * step


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
	_set_claw_launched(false)
	CombatEvents.entity_removed.emit(self, &"grapple", false)
	queue_free()


func _update_line() -> void:
	if _chain == null or owner_mech == null or not is_instance_valid(owner_mech):
		return
	var a := _chain_start()
	var b := global_position
	var d := b - a
	var len := d.length()
	var mm := _chain.multimesh
	if len < 0.05:
		mm.visible_instance_count = 0
		return
	var up := Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT
	var basis := Basis.looking_at(d, up)
	if _state == 0 or _state == 5:
		_head.global_basis = Basis.looking_at(-d if _state == 5 else d, up)  # claw faces where it flies
	var n := mini(int(len / LINK), mm.instance_count)
	_chain.global_transform = Transform3D.IDENTITY
	for i in n:
		var p := a + d * ((i + 0.5) * LINK / len)
		var lb := basis.rotated(d.normalized(), PI * 0.5) if i % 2 == 1 else basis  # alternate links
		mm.set_instance_transform(i, Transform3D(lb, p))
	mm.visible_instance_count = n
