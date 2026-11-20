class_name MirrorKit
extends MechKit
## PALE SERAPH 流光镜盾 heat (see MirrorConfig). Hooks used: defends_against
## (overheat / ultimate attacks), on_guarded (heat), on_guard_held
## (refraction). The F parry ignores heat; it only follows the ultimate rule.

var heat: float = 0.0
var overheated := false
var _since_block := 100.0


func cfg() -> MirrorConfig:
	return config as MirrorConfig


func setup(p_combat: CombatStateMachine, p_config: KitConfig) -> void:
	super.setup(p_combat, p_config if p_config else MirrorConfig.new())


func _judging() -> bool:
	return combat.ultimate != null and combat.ultimate.in_judgment()


## Is the mirror working right now (guard)?
func mirror_active() -> bool:
	return not overheated


func defends_against(hit: HitInfo, parry: bool) -> bool:
	if hit.attack.ultimate_attack and not _judging():
		return false  # an ultimate's light / shells go straight through
	return parry or not overheated


## Beams never break a working mirror: it reflects them (round 6). The
## heat they add (×beam_heat_mult) is the price.
func resists_guard_break(hit: HitInfo) -> bool:
	return hit.attack.attack_type == CombatTypes.AttackType.BEAM


func on_guarded(hit: HitInfo) -> void:
	var raw := hit.attack.damage * hit.damage_mult
	var k := cfg().heat_per_damage
	if hit.attack.attack_type == CombatTypes.AttackType.BEAM:
		k *= cfg().beam_heat_mult
	if _judging():
		k *= cfg().judgment_heat_mult
	heat = minf(heat + raw * k, cfg().max_heat)
	_since_block = 0.0
	CombatEvents.kit_event.emit(motor, &"mirror_heat")
	if heat >= cfg().max_heat and not overheated:
		overheated = true
		CombatEvents.kit_event.emit(motor, &"mirror_overheat")


func on_guard_held(hit: HitInfo) -> void:
	if hit.attack == cfg().ray_attack:
		return  # a reflected ray is not reflected again (no mirror ping-pong)
	var pr := hit.projectile as Projectile
	if pr and cfg().projectile_refract_mult > 0.0:
		Projectile.spawn_refraction(pr, motor, cfg().projectile_refract_mult, hit.hit_position)
		CombatEvents.kit_event.emit(motor, &"mirror_refract")
	elif hit.attack.attack_type == CombatTypes.AttackType.BEAM and cfg().ray_attack and cfg().beam_reflect_mult > 0.0:
		fire_ray(hit.attack.damage * hit.damage_mult * cfg().beam_reflect_mult)


## Reflected light: an instant ray from the mirror toward the crosshair;
## the first hostile on the line takes `dmg`; walls stop it.
func fire_ray(dmg: float) -> HitInfo:
	var origin := motor.global_position + Vector3.UP * 2.4 + motor.get_forward() * 1.0
	var aim := combat.reflect_point()
	var dir := aim - origin
	dir = dir.normalized() if dir.length() > 0.5 else motor.get_forward()
	var end := origin + dir * cfg().ray_range
	var space := motor.get_world_3d().direct_space_state
	var exclude: Array[RID] = [motor.get_rid()]
	if combat.hurtbox:
		exclude.append(combat.hurtbox.get_rid())
	var hit_point := end
	var out: HitInfo = null
	for i in 8:
		var q := PhysicsRayQueryParameters3D.create(origin, end, CombatTypes.WORLD_LAYER | CombatTypes.HURTBOX_LAYER)
		q.collide_with_areas = true
		q.exclude = exclude
		var r := space.intersect_ray(q)
		if r.is_empty():
			break
		var hb := r.collider as Hurtbox
		if hb == null:
			if r.collider is CollisionObject3D and ((r.collider as CollisionObject3D).collision_layer & CombatTypes.WORLD_LAYER) != 0:
				hit_point = r.position
				break  # a wall stops the light
			exclude.append((r.collider as CollisionObject3D).get_rid())
			continue
		if hb.mech == null or hb.mech == motor or not TeamRules.can_damage(motor, hb.mech):
			exclude.append(hb.get_rid())
			continue
		var hit := HitInfo.new()
		hit.attacker = motor
		hit.victim = hb.mech
		hit.attack = cfg().ray_attack
		hit.source_position = origin
		hit.hit_position = r.position
		hit.direction = dir
		hit.damage_mult = dmg / maxf(cfg().ray_attack.damage, 0.01)
		DamageSystem.resolve(hit)
		out = hit
		hit_point = r.position
		break
	if motor.is_inside_tree():
		LightRay.flash(motor.get_parent(), origin, hit_point, Color(0.75, 0.95, 1.0))
	CombatEvents.kit_event.emit(motor, &"mirror_ray")
	return out


func _physics_process(delta: float) -> void:
	if combat == null or motor.in_hitstop() or combat.is_dead():
		return
	_since_block += delta
	if overheated:
		heat = maxf(heat - cfg().overheat_cool_per_sec * delta, 0.0)
		if heat <= 0.0:
			overheated = false
			CombatEvents.kit_event.emit(motor, &"mirror_ready")
	elif _since_block >= cfg().cool_delay:
		heat = maxf(heat - cfg().cool_per_sec * delta, 0.0)


func reset() -> void:
	heat = 0.0
	overheated = false
	_since_block = 100.0


func hud_text() -> String:
	if overheated:
		return "镜盾过热！散热中 %.0f（举盾不减伤、不折射）" % heat
	var line := "镜盾热度 %3.0f / %.0f" % [heat, cfg().max_heat]
	if _judging():
		line += "  审判：耐热 ×2，可挡大招"
	return line


func hud_bar() -> float:
	return heat / cfg().max_heat
