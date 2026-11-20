class_name DamageSystem
extends RefCounted
## Single place where a hit's outcome is decided:
##   permission (TeamRules.can_damage) → evade (i-frames) → parry → guard → clean hit.
## Attack types: MELEE / PROJECTILE can be parried and guarded; BEAM /
## EXPLOSION can only be guarded; GRAB can only be dodged.
## Non-mech victims (turrets, missiles) take a plain hit.
## Detection (hitbox sweep / projectile ray) builds a HitInfo and calls
## resolve(); reactions are applied through the victim's / attacker's
## CombatStateMachine (which only touches MechMotor via modifiers,
## impulses and hitstop); presentation listens to CombatEvents.


static func get_combat(n: Node) -> CombatStateMachine:
	if n == null or not is_instance_valid(n):
		return null
	return n.get_node_or_null(^"CombatStateMachine") as CombatStateMachine


## True when `source` lies inside the victim's frontal guard / parry arc.
static func in_front_arc(victim: Node3D, source: Vector3, arc_deg: float) -> bool:
	var fwd := -victim.global_basis.z
	fwd.y = 0.0
	var to := source - victim.global_position
	to.y = 0.0
	if to.length() < 0.3 or fwd.length() < 0.01:
		return true
	return rad_to_deg(fwd.normalized().angle_to(to.normalized())) <= arc_deg * 0.5


static func resolve(hit: HitInfo) -> int:
	hit.result = _resolve(hit)
	if hit.result != CombatTypes.HitResult.IGNORED:
		var ac := get_combat(hit.attacker)
		if ac and ac.kit:
			ac.kit.on_hit_dealt(hit)
	CombatEvents.hit_resolved.emit(hit)
	return hit.result


## The attack connected (counts as "not a whiff").
static func is_landed(result: int) -> bool:
	return result == CombatTypes.HitResult.HIT or result == CombatTypes.HitResult.GUARDED \
		or result == CombatTypes.HitResult.GUARD_BREAK


## Plain hit on a non-mech damageable (turret, missile): it exposes `health`
## and `team_id`; no guard, no parry, no reactions.
static func _resolve_entity(hit: HitInfo) -> int:
	var victim := hit.victim
	if victim == null or not TeamRules.can_damage(hit.attacker, victim):
		return CombatTypes.HitResult.IGNORED
	var h := victim.get(&"health") as Health
	if h == null:
		return CombatTypes.HitResult.IGNORED
	hit.final_damage = hit.attack.damage * hit.damage_mult
	h.take(hit.final_damage)
	return CombatTypes.HitResult.HIT


static func _resolve(hit: HitInfo) -> int:
	var victim := hit.victim
	var vc := get_combat(victim)
	if vc == null:
		return _resolve_entity(hit)
	if not TeamRules.can_damage(hit.attacker, victim):
		return CombatTypes.HitResult.IGNORED
	if vc.is_invulnerable():
		return CombatTypes.HitResult.EVADED
	var atk := hit.attack
	var prof := vc.profile
	var front := in_front_arc(victim, hit.source_position, prof.guard_arc_deg)
	var is_proj := hit.projectile != null

	# --- parry (mirror shield): melee + projectiles, frontal arc only
	if not hit.force_unblockable and atk.parryable and CombatTypes.is_parryable_type(atk.attack_type) \
			and front and vc.is_parrying() and vc.kit.defends_against(hit, true):
		if is_proj:
			vc.on_parried_projectile(hit)
			# only a mirror refracts; HELLFANG / VERDANT swallow the shot (round 6)
			return CombatTypes.HitResult.REFLECTED if prof.parry_reflects else CombatTypes.HitResult.PARRIED
		return vc.on_parried_melee(hit)

	# --- guard: frontal arc, not grabs
	var base := atk.damage * hit.damage_mult
	if not hit.force_unblockable and atk.guardable and CombatTypes.is_guardable_type(atk.attack_type) \
			and front and vc.is_guarding() and vc.kit.defends_against(hit, false):
		var chip := base * vc.guard_ratio()
		vc.kit.on_guarded(hit)
		var breaks := (atk.guard_break or hit.force_guard_break) and not vc.kit.resists_guard_break(hit)
		if breaks or not vc.motor.consume_en(base * prof.guard_en_per_damage):
			hit.final_damage = chip
			vc.health.take(chip)
			vc.on_guard_broken(hit)
			_hitstop(hit, atk.hitstop * 1.5)
			if atk.status_on_guard:
				_apply_statuses(hit, vc)
			return CombatTypes.HitResult.GUARD_BREAK
		hit.final_damage = chip
		vc.health.take(chip)
		vc.motor.apply_impulse(_push(hit, atk.knockback * 0.4, 0.0))
		_hitstop(hit, atk.hitstop * 0.6)
		if atk.status_on_guard:
			_apply_statuses(hit, vc)
		vc.kit.on_guard_held(hit)  # PALE SERAPH mirror refraction
		return CombatTypes.HitResult.GUARDED

	# --- clean hit
	var mult := vc.damage_taken_mult(hit)
	var ac := get_combat(hit.attacker)
	if vc.offbalance_by == hit.attacker and ac and hit.attack != ac.profile.parry_riposte:
		mult *= ac.profile.counter_damage_mult  # punish window after a parry (the riposte carries its own)
	if atk.mark_consume_bonus > 0.0:
		mult *= 1.0 + atk.mark_consume_bonus * vc.status.consume(&"mark")
	hit.final_damage = base * mult
	vc.health.take(hit.final_damage)
	if not vc.health.dead:
		vc.on_clean_hit(hit, _push(hit, atk.knockback * hit.knockback_mult, atk.knockback_up))
		_apply_statuses(hit, vc)
	_hitstop(hit, atk.hitstop)
	return CombatTypes.HitResult.HIT


static func _apply_statuses(hit: HitInfo, vc: CombatStateMachine) -> void:
	for st in hit.attack.status_effects:
		vc.status.apply(st, hit.attacker)


static func _push(hit: HitInfo, strength: float, up: float) -> Vector3:
	var d := hit.direction
	d.y = 0.0
	if d.length() < 0.01:
		d = hit.victim.global_position - hit.source_position
		d.y = 0.0
	return d.normalized() * strength + Vector3.UP * up


## Hitstop is local: only the two mechs involved freeze (third parties keep
## moving). Projectile hits freeze only the victim.
static func _hitstop(hit: HitInfo, t: float) -> void:
	if t <= 0.0:
		return
	var vm := hit.victim as MechMotor
	if vm:
		vm.apply_hitstop(t)
	if hit.projectile == null:
		var am := hit.attacker as MechMotor
		if am:
			am.apply_hitstop(t)
