class_name CombatStateMachine
extends Node
## Combat / hit-reaction layer, independent from the motion layer.
## It influences movement ONLY through MovementModifier (restrictions and
## the `forced` motion correction for lunges), MechMotor.apply_impulse and
## MechMotor.apply_hitstop — it never writes motor velocity. No combat
## state blocks ALL control: gravity, camera, lock-on and (outside hard
## control) movement always stay live.
##
## Reads combat intent from the shared MechCommand (attack / skill / parry /
## ult edges, guard held), so player and AI brains drive it identically.

signal combat_state_changed(old_state: int, new_state: int)

enum CombatState { READY, ACTION, STAGGER, ATTACK, GUARD, PARRY, OFFBALANCE, ULT_WINDUP, DEAD, CHARGE }
const STATE_NAMES := ["READY", "ACTION", "STAGGER", "ATTACK", "GUARD", "PARRY", "OFFBALANCE", "ULT_WINDUP", "DEAD", "CHARGE"]

const MOD_ACTION := &"combat_action"
const MOD_STAGGER := &"combat_stagger"
const MOD_ATTACK := &"combat_attack"
const MOD_GUARD := &"combat_guard"
const MOD_PARRY := &"combat_parry"
const MOD_OFFBALANCE := &"combat_offbalance"
const MOD_ULT_WINDUP := &"combat_ult_windup"
const MOD_DEAD := &"combat_dead"
const MOD_CHARGE := &"combat_charge"
const INPUT_BUFFER := 0.25

@export var motor_path: NodePath = ^".."

var state: int = CombatState.READY
var state_timer: float = 0.0
var motor: MechMotor
var profile: CombatProfile
var health: Health
var hurtbox: Hurtbox
var ultimate: UltimateSystem
var kit: MechKit
var status: StatusEffects
## Current target, written by the brain (lock target / scripted target).
var aim_target: Node3D
## Set while this mech is off-balance from a parry: the parrier.
var offbalance_by: Node3D
## Combat clock (seconds, pauses during hitstop).
var time: float = 0.0
var last_parry_time: float = -100.0

# --- attack runtime
var attack: AttackDefinition
var attack_time: float = 0.0
var _hit_ids: Dictionary = {}
var _lunge_dir := Vector3.FORWARD
var _lunge_stopped := false
## Horizontally on top of the target: stop advancing, keep vertical tracking.
var _lunge_reached := false
var _projectile_fired := false
var _active_announced := false
var _attack_mod: MovementModifier
var _force_unblockable := false
var _attack_damage_mult := 1.0
var _pending_counter: Node3D
## Riposte window after a melee parry that knocked the attacker off-balance.
var riposte_target: Node3D
var riposte_left := 0.0
## Something landed (HIT / GUARDED / GUARD_BREAK) during the current attack.
var _landed := false
## Recovery added to the current attack (whiff, grapple miss).
var _extra_recovery := 0.0
## Charge level (0..1) the current attack was fired with.
var _shot_charge := 0.0
## Charge state level while holding the charge button.
var charge_level: float = 0.0
## Invulnerable (backstep i-frames) for this long.
var invuln_left: float = 0.0

# --- input buffers
var _buf_attack := 0.0
var _buf_skill := 0.0
var _buf_parry := 0.0
var _buf_ult := 0.0
var _buf_skill_hold := 0.0
var _buf_attack_hold := 0.0
## >= 0 while a press is pending its tap / hold decision.
var _skill_hold_t := -1.0
var _attack_hold_t := -1.0

# --- parry runtime
var _parry_window_left := 0.0
var _parry_success := false
var _parry_count := 0
var _parry_recovering := false

var _cooldowns: Dictionary = {}
var _cc_times: Array[float] = []
var cc_immune_left: float = 0.0


func _ready() -> void:
	motor = get_node_or_null(motor_path) as MechMotor
	if profile == null:
		profile = CombatProfile.new()
	process_physics_priority = -5  # after the brain, before the motor


## Called by MechFactory: builds Health, Hurtbox and UltimateSystem.
func setup(p_profile: CombatProfile, p_motor: MechMotor) -> void:
	profile = p_profile if p_profile else CombatProfile.new()
	motor = p_motor
	health = Health.new()
	health.name = "Health"
	p_motor.add_child(health)
	health.setup(profile.max_hp)
	health.died.connect(_on_died)
	hurtbox = Hurtbox.new()
	p_motor.add_child(hurtbox)
	hurtbox.setup(p_motor, 1.0, MechMotor.BODY_HEIGHT)
	if profile.ultimate:
		ultimate = UltimateSystem.new()
		ultimate.name = "UltimateSystem"
		p_motor.add_child(ultimate)
		ultimate.setup(profile.ultimate, self)
	status = StatusEffects.new()
	p_motor.add_child(status)
	status.setup(p_motor)
	kit = profile.kit.create_kit() if profile.kit else MechKit.new()
	p_motor.add_child(kit)
	kit.setup(self, profile.kit)


## Practice / debug: full HP, clear states, reset ultimate.
func restore_full() -> void:
	health.restore()
	hurtbox.set_enabled(true)
	for id in [MOD_STAGGER, MOD_OFFBALANCE, MOD_DEAD, MOD_ACTION]:
		motor.remove_modifier(id)
	offbalance_by = null
	riposte_target = null
	riposte_left = 0.0
	cc_immune_left = 0.0
	invuln_left = 0.0
	status.clear()
	kit.reset()
	_cc_times.clear()
	_cooldowns.clear()
	_to_ready()
	if ultimate:
		ultimate.reset()


func get_state_name() -> String:
	return STATE_NAMES[state]


func is_dead() -> bool:
	return state == CombatState.DEAD


func is_guarding() -> bool:
	return state == CombatState.GUARD


func is_parrying() -> bool:
	if state == CombatState.PARRY and not _parry_recovering:
		return true
	return state == CombatState.ULT_WINDUP and ultimate != null and ultimate.definition.windup_parries


func get_cooldown(id: StringName) -> float:
	return _cooldowns.get(id, 0.0)


func is_invulnerable() -> bool:
	return invuln_left > 0.0


func is_charging() -> bool:
	return state == CombatState.CHARGE


## 0 windup, 1 active, 2 recovery; -1 when not attacking.
func get_attack_phase() -> int:
	if state != CombatState.ATTACK or attack == null:
		return -1
	if attack_time < attack.windup:
		return 0
	return 1 if attack_time < attack.windup + maxf(attack.active, attack.lunge_duration) else 2


## Incoming damage multiplier from this mech's own state (whiffed parry,
## ultimate overload, statuses such as armor break, kit rules such as
## overheat).
func damage_taken_mult(hit: HitInfo = null) -> float:
	var m := 1.0
	if state == CombatState.PARRY and _parry_recovering:
		m *= profile.parry_whiff_damage_mult
	if ultimate:
		m *= ultimate.damage_taken_mult()
	m *= status.damage_taken_mult()
	m *= kit.incoming_mult(hit)
	return m


## Guard damage ratio after armor break / kit modifiers, clamped to [0, 1].
func guard_ratio() -> float:
	return clampf(profile.guard_damage_taken + status.guard_ratio_add() + kit.guard_ratio_add(), 0.0, 1.0)


## A delivery that resolves later (grapple, projectile) reports its outcome.
func report_delivery(def: AttackDefinition, landed: bool, extra_recovery: float = 0.0) -> void:
	if state == CombatState.ATTACK and attack == def:
		_landed = _landed or landed
		_extra_recovery += extra_recovery
	elif not landed and extra_recovery > 0.0 and state == CombatState.READY:
		start_action(extra_recovery, 0.3)  # cable still retracting after the attack ended


# ==========================================================================
# Main loop
# ==========================================================================

func _physics_process(delta: float) -> void:
	if motor == null or state == CombatState.DEAD:
		return
	var cmd := motor.command
	if cmd.attack_pressed:
		if profile.attack_hold and state == CombatState.READY and kit.can_start(profile.attack_hold) \
				and get_cooldown(profile.attack_hold.id) <= 0.0:
			_attack_hold_t = 0.0
		else:
			_buf_attack = INPUT_BUFFER
	if cmd.skill_pressed:
		if profile.skill_hold:
			_skill_hold_t = 0.0
		else:
			_buf_skill = INPUT_BUFFER
	if cmd.parry_pressed: _buf_parry = INPUT_BUFFER
	if cmd.ult_pressed and ultimate and ultimate.is_ready(): _buf_ult = INPUT_BUFFER
	if motor.in_hitstop():
		return
	time += delta
	_buf_attack = maxf(_buf_attack - delta, 0.0)
	_buf_skill = maxf(_buf_skill - delta, 0.0)
	_buf_parry = maxf(_buf_parry - delta, 0.0)
	_buf_ult = maxf(_buf_ult - delta, 0.0)
	_buf_skill_hold = maxf(_buf_skill_hold - delta, 0.0)
	_buf_attack_hold = maxf(_buf_attack_hold - delta, 0.0)
	cc_immune_left = maxf(cc_immune_left - delta, 0.0)
	invuln_left = maxf(invuln_left - delta, 0.0)
	_tick_holds(delta, cmd)
	for k in _cooldowns.keys():
		_cooldowns[k] = maxf(_cooldowns[k] - delta, 0.0)
	state_timer -= delta
	_tick_riposte(delta)

	if _pending_counter and is_instance_valid(_pending_counter) and TeamRules.is_alive(_pending_counter) \
			and ultimate and ultimate.definition.judgment_counter:
		aim_target = _pending_counter
		_pending_counter = null
		_clear_state_mods()
		_start_attack(ultimate.definition.judgment_counter, true)
		return
	_pending_counter = null

	match state:
		CombatState.READY:
			_ready_inputs(cmd)
		CombatState.GUARD:
			if _buf_ult > 0.0 and ultimate and ultimate.try_activate():
				_buf_ult = 0.0
			elif not cmd.guard_held:
				_to_ready()
			elif _buf_parry > 0.0:
				_defend()
			elif _buf_skill_hold > 0.0 and profile.skill_hold and _start_attack(profile.skill_hold):
				_buf_skill_hold = 0.0
			elif _buf_skill > 0.0 and _try_skill():
				pass
			elif _buf_attack > 0.0:
				_try_primary()
		CombatState.PARRY:
			if not (_parry_success and _buf_attack > 0.0 and _try_riposte()):
				_tick_parry(delta)
		CombatState.ATTACK:
			_tick_attack(delta, cmd)
		CombatState.ACTION, CombatState.STAGGER, CombatState.OFFBALANCE:
			if state_timer <= 0.0:
				offbalance_by = null
				_to_ready()
		CombatState.ULT_WINDUP:
			if state_timer <= 0.0:
				_to_ready()
				ultimate.enter_judgment()
		CombatState.CHARGE:
			_tick_charge(delta, cmd)


## Tap / hold decision for buttons that have a hold variant.
func _tick_holds(delta: float, cmd: MechCommand) -> void:
	if _skill_hold_t >= 0.0:
		_skill_hold_t += delta
		if not cmd.skill_held:
			_skill_hold_t = -1.0
			_buf_skill = INPUT_BUFFER  # released early: tap
		elif _skill_hold_t >= profile.hold_threshold:
			_skill_hold_t = -1.0
			_buf_skill_hold = INPUT_BUFFER
	if _attack_hold_t >= 0.0:
		_attack_hold_t += delta
		if not cmd.attack_held:
			_attack_hold_t = -1.0
			_buf_attack = INPUT_BUFFER
		elif _attack_hold_t >= profile.hold_threshold:
			_attack_hold_t = -1.0
			_buf_attack_hold = INPUT_BUFFER


func _ready_inputs(cmd: MechCommand) -> void:
	if _buf_ult > 0.0 and (ultimate == null or not ultimate.is_ready()):
		_buf_ult = 0.0  # a press while unavailable is not kept for later
	if _buf_ult > 0.0 and ultimate and ultimate.try_activate():
		_buf_ult = 0.0
		return
	if _buf_parry > 0.0:
		_defend()
		return
	if _buf_attack > 0.0 and _try_riposte():
		return
	if _buf_skill_hold > 0.0:
		_buf_skill_hold = 0.0
		if _start_attack(profile.skill_hold):
			return
	if _buf_attack_hold > 0.0:
		_buf_attack_hold = 0.0
		if _start_attack(profile.attack_hold):
			return
	if _buf_skill > 0.0 and _try_skill():
		return
	if _buf_attack > 0.0 and _try_primary():
		return
	if _attack_hold_t >= 0.0 or _skill_hold_t >= 0.0:
		return  # a press is still deciding tap / hold
	if cmd.guard_held:
		if profile.charge_attack:
			_enter_charge()
		else:
			_enter_guard()


## F: parry, or the mech's own defence action (backstep).
func _defend() -> void:
	_buf_parry = 0.0
	if profile.defense_action:
		_start_attack(profile.defense_action)
	else:
		_start_parry()


# ==========================================================================
# Attacks
# ==========================================================================

func _try_primary() -> bool:
	if profile.light_combo:
		return _start_attack(profile.light_combo)
	if profile.ranged:
		return _start_attack(profile.ranged)
	return false


func _try_skill() -> bool:
	_buf_skill = 0.0
	if ultimate and ultimate.in_judgment() and ultimate.spear_charges_left > 0:
		if _start_attack(ultimate.definition.final_spear):
			ultimate.spear_charges_left -= 1
			return true
		return false
	return _start_attack(profile.skill)


## Starts `def`. Returns false when on cooldown / not enough EN / the kit
## refuses (heat, deploy limit, overheat).
func _start_attack(def: AttackDefinition, unblockable := false, dmg_mult := 1.0, charge := 0.0) -> bool:
	if def == null or get_cooldown(def.id) > 0.0:
		return false
	if kit.blocks_actions() or not kit.can_start(def):
		return false
	if def.en_cost > 0.0 and not motor.consume_en(def.en_cost * motor.get_en_cost_mult()):
		return false
	if def.cooldown > 0.0:
		_cooldowns[def.id] = def.cooldown
	_finish_attack()
	_clear_state_mods()
	attack = def
	attack_time = 0.0
	_hit_ids.clear()
	_lunge_stopped = false
	_lunge_reached = false
	_projectile_fired = false
	_active_announced = false
	_landed = false
	_extra_recovery = 0.0
	_shot_charge = charge
	_force_unblockable = unblockable
	_attack_damage_mult = dmg_mult * kit.outgoing_mult(def)
	_buf_attack = 0.0
	_lunge_dir = _dir_to_target()
	_attack_mod = MovementModifier.create(MOD_ATTACK)
	motor.add_modifier(_attack_mod)
	_enter(CombatState.ATTACK)
	_update_attack_mod(0, 0.0)
	kit.on_attack_started(def)
	CombatEvents.attack_started.emit(motor, def)
	if def.telegraphed:
		CombatEvents.telegraph.emit(motor, def, def.windup)
	return true


## Tells the kit the current attack is over (finished, chained or interrupted).
func _finish_attack() -> void:
	if attack and state == CombatState.ATTACK:
		var def := attack
		var landed := _landed
		attack = null  # re-entrancy: kit may start something
		kit.on_attack_finished(def, landed)
		CombatEvents.attack_finished.emit(motor, def, landed)


func _tick_attack(delta: float, cmd: MechCommand) -> void:
	var d := attack
	attack_time += delta
	var t_active_end := d.windup + maxf(d.active, d.lunge_duration)
	var phase := 0 if attack_time < d.windup else (1 if attack_time < t_active_end else 2)
	if phase >= 1 and not _active_announced:
		_active_announced = true
		CombatEvents.attack_active.emit(motor, d)
		kit.on_attack_active(d)
		if state != CombatState.ATTACK or attack != d:
			return
		_on_active_start(d)
		if state != CombatState.ATTACK or attack != d:
			return

	if d.get_delivery() == CombatTypes.Delivery.HITBOX:
		if phase == 1:
			_sweep_hitbox()
			if state != CombatState.ATTACK:
				return  # got parried during the sweep
	_update_attack_mod(phase, delta)
	# whiffed heavy swing: longer recovery
	if phase == 2 and not _landed and d.get_delivery() == CombatTypes.Delivery.HITBOX and d.whiff_recovery_extra > 0.0 \
			and _extra_recovery < d.whiff_recovery_extra:
		_extra_recovery = d.whiff_recovery_extra

	# combo chain at the end of the active phase
	if attack_time >= t_active_end and _buf_attack > 0.0 and d.next_attack:
		_start_attack(d.next_attack)
		return
	# cancel window: recovery can be cancelled into defence / skill / movement
	# (a whiff pushes the window back by the extra recovery)
	if attack_time >= d.cancel_time + _extra_recovery:
		if _buf_parry > 0.0:
			_defend()
			return
		if phase == 2 and cmd.guard_held and not profile.charge_attack:
			_enter_guard()
			return
		if phase == 2 and _buf_skill_hold > 0.0 and profile.skill_hold and _start_attack(profile.skill_hold):
			_buf_skill_hold = 0.0
			return
		if phase == 2 and _buf_skill > 0.0 and _try_skill():
			return
		if phase == 2 and (cmd.dash_pressed or cmd.jump_pressed):
			_to_ready()
			return
	if attack_time >= d.total_time() + _extra_recovery:
		_to_ready()


## Delivery at the start of the active phase.
func _on_active_start(d: AttackDefinition) -> void:
	match d.get_delivery():
		CombatTypes.Delivery.PROJECTILE:
			_fire_projectile()
		CombatTypes.Delivery.GRAPPLE:
			var g := Grapple.new()
			motor.get_parent().add_child(g)
			g.launch(self, d, _muzzle(), _aim_dir(_muzzle()))
		CombatTypes.Delivery.ORBITAL:
			OrbitalStrike.call_strike(self, d)
		CombatTypes.Delivery.DEPLOY:
			Deployables.deploy(self, d)
		CombatTypes.Delivery.SELF:
			pass
	if d.invuln_time > 0.0:
		invuln_left = d.invuln_time
	if d.repulse_radius > 0.0:
		_repulse(d)


## Non-damaging push on nearby hostile mechs (backstep pulse). Cover blocks it.
func _repulse(d: AttackDefinition) -> void:
	var c := motor.global_position + Vector3.UP * 2.0
	for t in TeamRules.get_valid_targets(motor, &"mechs"):
		var tm := t as MechMotor
		if tm == null:
			continue
		var p := tm.global_position + Vector3.UP * 2.0
		if c.distance_to(p) > d.repulse_radius or not CombatTypes.has_line_of_sight(motor.get_world_3d(), c, p):
			continue
		var push := tm.global_position - motor.global_position
		push.y = 0.0
		tm.apply_impulse(push.normalized() * d.repulse_force + Vector3.UP * 1.5)
		var tc := DamageSystem.get_combat(tm)
		if tc and (tc.state == CombatState.ATTACK or tc.state == CombatState.CHARGE):
			tc.interrupt()
	CombatEvents.kit_event.emit(motor, &"repulse")


func _update_attack_mod(phase: int, delta: float) -> void:
	var d := attack
	var m := _attack_mod
	m.speed_mult = [d.windup_speed_mult, d.active_speed_mult, d.recovery_speed_mult][phase]
	m.turn_mult = d.turn_mult
	m.block_dash = attack_time < d.cancel_time
	m.block_jump = attack_time < d.cancel_time
	var lunge_t := attack_time - d.windup
	var lunging := phase == 1 and absf(d.lunge_speed) > 0.0 and lunge_t < d.lunge_duration and not _lunge_stopped
	if lunging and d.stop_on_wall and lunge_t > 0.05 and motor.is_on_wall():
		_lunge_stopped = true
		lunging = false
	if lunging and d.lunge_speed > 0.0 and _target_valid():
		var to := _target_point() - (motor.global_position + Vector3.UP * 2.0)
		if Vector2(to.x, to.z).length() < 2.2:
			_lunge_reached = true  # on top of the target: no overshoot / no suction
	m.forced = lunging
	if lunging:
		var vy := 0.0
		if _target_valid():
			var to := _target_point() - (motor.global_position + Vector3.UP * 2.0)
			var flat := Vector3(to.x, 0.0, to.z)
			if d.lunge_steer_deg > 0.0 and flat.length() > 0.5 and delta > 0.0:
				var ang := _lunge_dir.signed_angle_to(flat.normalized(), Vector3.UP)
				var mx := deg_to_rad(d.lunge_steer_deg) * delta
				_lunge_dir = _lunge_dir.rotated(Vector3.UP, clampf(ang, -mx, mx)).normalized()
			if d.vertical_track_speed > 0.0 and absf(to.y) <= d.vertical_track_range:
				var remaining := maxf(d.lunge_duration - lunge_t, 0.05)
				vy = clampf(to.y / remaining, -d.vertical_track_speed, d.vertical_track_speed)
		m.forced_velocity = (Vector3.ZERO if _lunge_reached else _lunge_dir * d.lunge_speed) + Vector3.UP * vy
	motor.refresh_modifiers()


func _sweep_hitbox() -> void:
	var d := attack
	var space := motor.get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = d.hitbox_size
	var yaw := Basis(Vector3.UP, motor.global_rotation.y)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(yaw, motor.global_position + yaw * d.hitbox_offset)
	q.collision_mask = CombatTypes.HURTBOX_LAYER
	q.collide_with_areas = true
	q.collide_with_bodies = false
	for r in space.intersect_shape(q, 8):
		var hb := r.collider as Hurtbox
		if hb == null or hb.mech == motor or hb.mech == null:
			continue
		var id := hb.mech.get_instance_id()
		if _hit_ids.has(id):
			continue  # one hit per target per attack
		_hit_ids[id] = true
		var hit := HitInfo.new()
		hit.attacker = motor
		hit.victim = hb.mech
		hit.attack = d
		hit.source_position = motor.global_position
		hit.hit_position = hb.mech.global_position + Vector3.UP * 2.2
		hit.direction = (hb.mech.global_position - motor.global_position).normalized()
		hit.damage_mult = _attack_damage_mult
		hit.force_unblockable = _force_unblockable
		var res := DamageSystem.resolve(hit)
		if res == CombatTypes.HitResult.PARRIED or res == CombatTypes.HitResult.DEFLECTED:
			return
		if DamageSystem.is_landed(res):
			_landed = true


func _fire_projectile() -> void:
	_projectile_fired = true
	var d := attack
	var origin := _muzzle()
	var dir := _aim_dir(origin)
	var spec := d.projectile_spec
	var n := spec.pellets if spec else 1
	var speed := d.projectile_speed
	var dmg := _attack_damage_mult
	var guard_break := false
	if spec and charge_level_used() > 0.0:
		var k := inverse_lerp(profile.charge_min, 1.0, _shot_charge) if profile.charge_min < 1.0 else 1.0
		k = clampf(k, 0.0, 1.0)
		dmg *= lerpf(1.0, spec.charge_damage_mult, k)
		speed *= lerpf(1.0, spec.charge_speed_mult, k)
		guard_break = _shot_charge >= spec.charge_guard_break_at
	var right := dir.cross(Vector3.UP)
	if right.length() < 0.01:
		right = motor.global_basis.x
	right = right.normalized()
	for i in n:
		var pdir := dir
		if n > 1 and spec.spread_deg > 0.0:
			# deterministic fan: evenly across the cone horizontally, alternating slightly vertically
			var a := deg_to_rad(spec.spread_deg) * (float(i) / float(n - 1) - 0.5)
			var v := deg_to_rad(spec.spread_deg) * 0.25 * (1.0 if i % 2 == 0 else -1.0)
			pdir = pdir.rotated(Vector3.UP, a)
			pdir = pdir.rotated(right, v).normalized()
		var p := Projectile.new()
		motor.get_parent().add_child(p)
		p.global_position = origin
		p.launch(motor, d, pdir * speed, dmg)
		p.guard_break = guard_break
		if spec and spec.homing_deg > 0.0 and _target_valid():
			p.homing_deg = spec.homing_deg
			p.homing_target = aim_target


## Charge the current shot was fired with (0 = not a charge attack).
func charge_level_used() -> float:
	return _shot_charge


func _muzzle() -> Vector3:
	return motor.global_position + Vector3.UP * 2.6 + motor.get_forward() * 1.6


## Aim at the lock target if any (projectiles may fire upward: anti-air),
## otherwise straight ahead.
func _aim_dir(origin: Vector3) -> Vector3:
	if _target_valid():
		var to := _target_point() - origin
		if to.length() > 0.5:
			return to.normalized()
	return motor.get_forward()


func _dir_to_target() -> Vector3:
	if _target_valid():
		var to := _target_point() - motor.global_position
		to.y = 0.0
		if to.length() > 0.5:
			return to.normalized()
	return motor.get_forward()


func _target_valid() -> bool:
	return aim_target != null and is_instance_valid(aim_target) and TeamRules.is_alive(aim_target)


func _target_point() -> Vector3:
	if aim_target.has_method(&"get_lock_point"):
		return aim_target.call(&"get_lock_point")
	return aim_target.global_position + Vector3.UP * 2.0


# ==========================================================================
# Charge (right button held: AZURE ORACLE railgun)
# ==========================================================================

func _enter_charge() -> void:
	_clear_state_mods()
	charge_level = 0.0
	var m := MovementModifier.create(MOD_CHARGE)
	m.speed_mult = profile.charge_speed_mult
	m.block_dash = true
	m.turn_mult = 0.6
	motor.add_modifier(m)
	_enter(CombatState.CHARGE)
	# the visible aiming laser IS the telegraph (warning on the target)
	CombatEvents.telegraph.emit(motor, profile.charge_attack, profile.charge_time)
	CombatEvents.charge_changed.emit(motor, 0.0)


func _tick_charge(delta: float, cmd: MechCommand) -> void:
	charge_level = minf(charge_level + delta / maxf(profile.charge_time, 0.05), 1.0)
	CombatEvents.charge_changed.emit(motor, charge_level)
	if _buf_parry > 0.0:
		charge_level = 0.0
		CombatEvents.charge_changed.emit(motor, -1.0)
		_to_ready()
		_defend()
		return
	if cmd.guard_held:
		return
	var lvl := charge_level
	charge_level = 0.0
	CombatEvents.charge_changed.emit(motor, -1.0)
	_to_ready()
	if lvl >= profile.charge_min:
		_start_attack(profile.charge_attack, false, 1.0, lvl)


# ==========================================================================
# Defence
# ==========================================================================

func _enter_guard() -> void:
	_clear_state_mods()
	var m := MovementModifier.create(MOD_GUARD)
	m.speed_mult = profile.guard_speed_mult
	m.block_dash = true
	motor.add_modifier(m)
	_enter(CombatState.GUARD)


func _start_parry() -> void:
	_buf_parry = 0.0
	_clear_state_mods()
	_parry_window_left = profile.parry_window * (ultimate.parry_window_mult() if ultimate else 1.0)
	_parry_success = false
	_parry_count = 0
	_parry_recovering = false
	var m := MovementModifier.create(MOD_PARRY)
	m.speed_mult = 0.5
	m.block_dash = true
	m.block_jump = true
	motor.add_modifier(m)
	_enter(CombatState.PARRY)


func _tick_parry(delta: float) -> void:
	if not _parry_recovering:
		_parry_window_left -= delta
		if _parry_window_left <= 0.0:
			if _parry_success:
				_to_ready()  # success: no whiff recovery
			else:
				_parry_recovering = true
				state_timer = profile.parry_whiff_recovery
	elif state_timer <= 0.0:
		_to_ready()


## Called by DamageSystem when a melee hit lands inside our parry window.
func on_parried_melee(hit: HitInfo) -> int:
	_parry_count += 1
	_parry_success = true
	last_parry_time = time
	var first := _parry_count == 1
	var attacker := hit.attacker as MechMotor
	var ac := DamageSystem.get_combat(attacker)
	var push := attacker.global_position - motor.global_position
	push.y = 0.0
	push = push.normalized()
	motor.apply_hitstop(profile.parry_hitstop)
	if attacker:
		attacker.apply_hitstop(profile.parry_hitstop)
	if ac:
		if first and profile.parry_causes_offbalance:
			ac.apply_offbalance(profile.offbalance_time, push * profile.offbalance_knockback + Vector3.UP, motor)
		else:
			# push-back parry (and later attackers in a multi-parry): interrupted and pushed
			ac.interrupt()
			attacker.apply_impulse(push * profile.offbalance_knockback * 0.6)
	CombatEvents.parried.emit(motor, attacker, false)
	if state == CombatState.ULT_WINDUP:
		_to_ready()
		ultimate.enter_judgment()
	elif first and ultimate and ultimate.in_judgment():
		_pending_counter = attacker  # 裁决反击 on our next tick
	if first and profile.parry_riposte and _pending_counter == null and not (ultimate and ultimate.in_judgment()) \
			and ac and ac.state == CombatState.OFFBALANCE and ac.offbalance_by == motor:
		riposte_target = attacker
		riposte_left = maxf(ac.state_timer, 0.0)
		CombatEvents.riposte_window.emit(motor, attacker, riposte_left)
	return CombatTypes.HitResult.PARRIED if first else CombatTypes.HitResult.DEFLECTED


func _riposte_valid() -> bool:
	if riposte_left <= 0.0 or riposte_target == null or not is_instance_valid(riposte_target) \
			or not TeamRules.is_alive(riposte_target):
		return false
	var tc := DamageSystem.get_combat(riposte_target)
	return tc != null and tc.state == CombatState.OFFBALANCE and tc.offbalance_by == motor


func _tick_riposte(delta: float) -> void:
	if riposte_target == null:
		return
	riposte_left -= delta
	if not _riposte_valid():
		_close_riposte()


func _close_riposte() -> void:
	riposte_target = null
	riposte_left = 0.0
	CombatEvents.riposte_window.emit(motor, null, 0.0)


## Attack pressed inside the riposte window: 反刺 aimed at the parried attacker.
func _try_riposte() -> bool:
	if profile.parry_riposte == null or not _riposte_valid():
		return false
	var t := riposte_target
	_close_riposte()
	_buf_attack = 0.0
	aim_target = t
	return _start_attack(profile.parry_riposte, true)


## Called by DamageSystem when a projectile hits our parry window: the
## mirror shield refracts it back toward its shooter.
func on_parried_projectile(hit: HitInfo) -> void:
	_parry_success = true
	last_parry_time = time
	var dm := profile.reflect_damage_mult
	var sm := profile.reflect_speed_mult
	var homing := 0.0
	if ultimate and ultimate.in_judgment():
		dm = ultimate.definition.reflect_damage_mult
		sm = ultimate.definition.reflect_speed_mult
		homing = ultimate.definition.reflect_homing_deg
	(hit.projectile as Projectile).reflect(motor, dm, sm, homing)
	CombatEvents.parried.emit(motor, hit.attacker, true)
	if state == CombatState.ULT_WINDUP:
		_to_ready()
		ultimate.enter_judgment()


func on_guard_broken(hit: HitInfo) -> void:
	apply_stagger(profile.guard_break_stagger, DamageSystem._push(hit, hit.attack.knockback, 0.5))


func on_clean_hit(hit: HitInfo, push: Vector3) -> void:
	if hit.attack.stagger_time > 0.0:
		apply_stagger(hit.attack.stagger_time, push)
	else:
		motor.apply_impulse(push)


# ==========================================================================
# Hard control (with diminishing returns) / interrupts
# ==========================================================================

## Duration after hard-control protection: each CC in the last cc_window
## seconds scales the next by cc_decay; after cc_immunity_after the mech is
## briefly immune. Returns 0 when immune.
func cc_duration(base: float) -> float:
	if cc_immune_left > 0.0:
		return 0.0
	var recent: Array[float] = []
	for t in _cc_times:
		if time - t <= profile.cc_window:
			recent.append(t)
	_cc_times = recent
	var n := _cc_times.size()
	if n >= profile.cc_immunity_after:
		cc_immune_left = profile.cc_immunity_time
		_cc_times.clear()
		return 0.0
	_cc_times.append(time)
	return base * pow(profile.cc_decay, n)


## Hit reaction: blocks steering and thrust (an airborne mech falls) for
## the protected duration, pushes with an impulse, interrupts actions.
func apply_stagger(duration: float, knockback: Vector3 = Vector3.ZERO) -> void:
	if state == CombatState.DEAD:
		return
	if knockback != Vector3.ZERO:
		motor.apply_impulse(knockback)
	var d := cc_duration(duration)
	if d <= 0.0:
		return
	interrupt()
	_add_cc_mod(MOD_STAGGER, d)
	_enter(CombatState.STAGGER, d)


func apply_offbalance(duration: float, knockback: Vector3, by: Node3D) -> void:
	if state == CombatState.DEAD:
		return
	interrupt()
	motor.apply_impulse(knockback)
	var d := cc_duration(duration)
	if d <= 0.0:
		return
	offbalance_by = by
	_add_cc_mod(MOD_OFFBALANCE, d)
	_enter(CombatState.OFFBALANCE, d)


func _add_cc_mod(id: StringName, d: float) -> void:
	var m := MovementModifier.create(id, d)
	m.block_move = true
	m.block_dash = true
	m.block_jump = true
	m.block_thrust = true
	m.block_facing = true
	motor.add_modifier(m)


## Cancels the current attack / defence / ultimate windup.
func interrupt() -> void:
	if state == CombatState.ULT_WINDUP and ultimate:
		ultimate.on_windup_interrupted()
	if state == CombatState.CHARGE:
		charge_level = 0.0
		CombatEvents.charge_changed.emit(motor, -1.0)
	if state == CombatState.ATTACK or state == CombatState.GUARD or state == CombatState.PARRY \
			or state == CombatState.ULT_WINDUP or state == CombatState.ACTION or state == CombatState.CHARGE:
		_to_ready()


## Legacy generic action placeholder (2a tests): slows movement, blocks dash.
func start_action(duration: float, speed_mult: float = 0.4, block_thrust: bool = false) -> bool:
	if state == CombatState.STAGGER or state == CombatState.OFFBALANCE or state == CombatState.DEAD:
		return false
	_clear_state_mods()
	var m := MovementModifier.create(MOD_ACTION, duration)
	m.speed_mult = speed_mult
	m.block_dash = true
	m.block_jump = true
	m.block_thrust = block_thrust
	m.turn_mult = 0.5
	motor.add_modifier(m)
	_enter(CombatState.ACTION, duration)
	return true


func start_ult_windup(duration: float) -> void:
	_clear_state_mods()
	var m := MovementModifier.create(MOD_ULT_WINDUP)
	m.speed_mult = 0.2
	m.block_dash = true
	m.block_jump = true
	motor.add_modifier(m)
	_enter(CombatState.ULT_WINDUP, duration)
	CombatEvents.telegraph.emit(motor, null, duration)


# ==========================================================================
# Death / helpers
# ==========================================================================

func _on_died() -> void:
	_finish_attack()
	_clear_state_mods()
	for id in [MOD_STAGGER, MOD_OFFBALANCE, MOD_ACTION]:
		motor.remove_modifier(id)
	var m := MovementModifier.create(MOD_DEAD)
	m.speed_mult = 0.0
	m.block_move = true
	m.block_dash = true
	m.block_jump = true
	m.block_thrust = true
	m.block_facing = true
	motor.add_modifier(m)
	hurtbox.set_enabled(false)
	if ultimate:
		ultimate.on_owner_died()
	_enter(CombatState.DEAD)
	CombatEvents.mech_died.emit(motor)


func _clear_state_mods() -> void:
	for id in [MOD_ATTACK, MOD_GUARD, MOD_PARRY, MOD_ULT_WINDUP, MOD_ACTION, MOD_CHARGE]:
		motor.remove_modifier(id)
	_attack_mod = null
	attack = null


func _to_ready() -> void:
	_finish_attack()
	_clear_state_mods()
	_enter(CombatState.READY)


func _enter(s: int, duration: float = 0.0) -> void:
	var old := state
	state = s
	state_timer = duration
	if old != s:
		combat_state_changed.emit(old, s)
