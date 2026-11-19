class_name DeployKit
extends MechKit
## VERDANT ARK 部署. At most `max_turrets` turrets at a time (each expires
## on its own timer, and can be destroyed); the deploy skills have their
## own cooldowns (AttackDefinition.cooldown). Near its own turrets the ark
## is tougher (fortress).


func cfg() -> DeployConfig:
	return config as DeployConfig


func setup(p_combat: CombatStateMachine, p_config: KitConfig) -> void:
	super.setup(p_combat, p_config if p_config else DeployConfig.new())


func turrets() -> Array[Node3D]:
	return Deployables.owned_by(motor, DeploySpec.Kind.TURRET)


func can_start(def: AttackDefinition) -> bool:
	if def.get_delivery() == CombatTypes.Delivery.DEPLOY and def.deploy_spec and def.deploy_spec.kind == DeploySpec.Kind.TURRET:
		return turrets().size() < cfg().max_turrets
	return true


func in_fortress() -> bool:
	for t in turrets():
		if t.global_position.distance_to(motor.global_position) <= cfg().fortress_radius:
			return true
	return false


func incoming_mult(_hit: HitInfo) -> float:
	return cfg().fortress_damage_taken if in_fortress() else 1.0


func reset() -> void:
	for t in turrets():
		t.call(&"_remove", false)
	for z in Deployables.owned_by(motor, DeploySpec.Kind.ZONE):
		z.queue_free()


func hud_text() -> String:
	var parts: PackedStringArray = []
	for t in turrets():
		parts.append("%.0fs" % float(t.call(&"time_left")))
	var line := "炮台 %d / %d%s" % [parts.size(), cfg().max_turrets, ("  [" + ", ".join(parts) + "]") if not parts.is_empty() else ""]
	var p := combat.profile
	if p.skill and p.skill.cooldown > 0.0 and combat.get_cooldown(p.skill.id) > 0.0:
		line += "  部署冷却 %.1fs" % combat.get_cooldown(p.skill.id)
	if p.skill_hold and combat.get_cooldown(p.skill_hold.id) > 0.0:
		line += "  束缚区冷却 %.1fs" % combat.get_cooldown(p.skill_hold.id)
	if in_fortress():
		line += "  堡垒（受伤 ×%.2f）" % cfg().fortress_damage_taken
	return line
