class_name ArkRevivalEffect
extends UltimateEffect
## VERDANT ARK 方舟苏生 (ARK REVIVAL). The seed core wakes: a habitat grows
## around the ark and, since round 6 (移动方舟), travels with it. Deploy
## cooldowns are cleared and two back cannons grow out of the shell (they
## replace the old turret refill). Inside the habitat turrets fire faster,
## reach farther and mend, the ark mends and takes less damage, and hostile
## mechs are slowed (the whole field, not only the rim). Cost: dormancy
## (slow, no deploying). PROTOTYPE values (待测试).

@export var habitat_radius: float = 15.0
@export var edge_width: float = 3.0
@export var edge_status: StatusEffectDefinition
@export var turret_rate_mult: float = 1.5
@export var turret_regen_per_sec: float = 5.0
@export var turret_range_bonus: float = 8.0
## Fraction of max HP per second while the ark stands in its habitat.
@export var owner_regen_frac: float = 0.02
@export var owner_damage_taken: float = 0.75
@export var dormancy_speed_mult: float = 0.6
@export_group("Moving ark (round 6)")
## The habitat follows the ark instead of staying where it woke.
@export var follow_owner: bool = true
## The slow status covers the whole habitat (false: only the rim).
@export var whole_field: bool = true
## Old behaviour: grow turrets up to the limit on activation.
@export var refill_turrets: bool = false
@export var cannon_shot: AttackDefinition
@export var cannon_count: int = 2
@export var cannon_range: float = 32.0
@export var cannon_interval: float = 0.6
@export var cannon_turn_deg: float = 180.0

const MOD_DORMANT := &"ark_dormant"


func begin(us: UltimateSystem) -> void:
	var m := us.combat.motor
	var h := Habitat.new()
	m.get_parent().add_child(h)
	h.global_position = OrbitalStrike.ground_point(m.get_world_3d(), m.global_position + Vector3.UP * 2.0)
	h.setup(m, self)
	us.fx["habitat"] = h
	var dk := us.combat.kit as DeployKit
	if dk:
		dk.habitat = h
		dk.revive(refill_turrets)
	var cannons: Array = []
	if cannon_shot:
		for i in cannon_count:
			var bc := BackCannon.new()
			m.add_child(bc)
			var side := -1.0 if i % 2 == 0 else 1.0
			bc.setup(m, cannon_shot, cannon_range, cannon_interval, cannon_turn_deg, Vector3(0.95 * side, 4.3, 0.7))
			cannons.append(bc)
	us.fx["cannons"] = cannons
	CombatEvents.kit_event.emit(m, &"back_cannons")


func end(us: UltimateSystem) -> void:
	var h: Habitat = us.fx.get("habitat")
	if h and is_instance_valid(h):
		h.remove()
	for bc in us.fx.get("cannons", []):
		if bc and is_instance_valid(bc):
			(bc as Node).queue_free()
	us.fx.erase("cannons")
	var dk := us.combat.kit as DeployKit
	if dk:
		dk.habitat = null


func begin_cost(us: UltimateSystem) -> void:
	var mod := MovementModifier.create(MOD_DORMANT)
	mod.speed_mult = dormancy_speed_mult
	us.combat.motor.add_modifier(mod)
	var dk := us.combat.kit as DeployKit
	if dk:
		dk.dormant = true


func end_cost(us: UltimateSystem) -> void:
	us.combat.motor.remove_modifier(MOD_DORMANT)
	var dk := us.combat.kit as DeployKit
	if dk:
		dk.dormant = false


func hud_active(us: UltimateSystem) -> String:
	var h: Habitat = us.fx.get("habitat")
	var inside := h != null and is_instance_valid(h) and h.contains(us.combat.motor)
	return "移动栖地 %.0f m · 背甲炮 ×%d%s" % [habitat_radius, cannon_count if cannon_shot else 0, "（回血、受伤 ×%.2f）" % owner_damage_taken if inside else "（已离开栖地）"]
