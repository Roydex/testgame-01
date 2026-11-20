class_name MarkKit
extends MechKit
## AZURE ORACLE 标记与蓄力. Pulse hits put visible coordinate marks on the
## victim (anyone can see them); the railgun consumes them for bonus damage
## and the orbital strike uses them to shrink its circle. The railgun charge
## is the generic CombatStateMachine CHARGE state. This kit only reports.


func cfg() -> MarkConfig:
	return config as MarkConfig


func setup(p_combat: CombatStateMachine, p_config: KitConfig) -> void:
	super.setup(p_combat, p_config if p_config else MarkConfig.new())


func target_marks() -> int:
	var tc := DamageSystem.get_combat(combat.ranged_target())
	return tc.status.stacks(cfg().mark_id) if tc else 0


func hud_text() -> String:
	var line := "目标标记 %d / 3" % target_marks()
	if combat.is_charging():
		line += "  磁轨蓄力 %3.0f%%%s" % [combat.charge_level * 100.0, "  满蓄：破防" if combat.charge_level >= 0.99 else ""]
	var p := combat.profile
	if p.defense_action and combat.get_cooldown(p.defense_action.id) > 0.0:
		line += "  后跃冷却 %.1fs" % combat.get_cooldown(p.defense_action.id)
	if p.skill and combat.get_cooldown(p.skill.id) > 0.0:
		line += "  导弹 %.1fs" % combat.get_cooldown(p.skill.id)
	if p.skill_hold and combat.get_cooldown(p.skill_hold.id) > 0.0:
		line += "  轨道 %.1fs" % combat.get_cooldown(p.skill_hold.id)
	return line


func hud_bar() -> float:
	return combat.charge_level if combat.is_charging() else -1.0
