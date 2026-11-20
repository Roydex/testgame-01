class_name ArkRevivalEffect
extends UltimateEffect
## VERDANT ARK 方舟苏生 (ARK REVIVAL). The seed core wakes: a habitat grows
## around the ark. Turrets are refilled and deploy cooldowns cleared; inside
## the habitat turrets fire faster, reach farther and mend, the ark mends
## and takes less damage; its rim slows enemies. Cost: dormancy (slow, no
## deploying). PROTOTYPE values (待测试).

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
		dk.revive()


func end(us: UltimateSystem) -> void:
	var h: Habitat = us.fx.get("habitat")
	if h and is_instance_valid(h):
		h.remove()
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
	return "栖地 %.0f m%s" % [habitat_radius, "（在栖地内：回血、受伤 ×%.2f）" % owner_damage_taken if inside else "（已离开栖地）"]
