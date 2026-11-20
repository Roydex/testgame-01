class_name BackdraftEffect
extends UltimateEffect
## HELLFANG 熔炉逆燃 (FURNACE BACKDRAFT). The safety valve melts: heat is
## pinned at max without overheating, every attack gets the scorching bonus,
## the grapple cools down fast and a heat wave burns everything close by.
## Cost: a long, harsh overheat (no attacks, no dashing). The user chose the
## version without lifesteal (2026-11-20). PROTOTYPE values (待测试).

@export var aura_attack: AttackDefinition
@export var aura_radius: float = 6.0
@export var aura_interval: float = 0.5
@export var hook_cooldown: float = 1.0
@export var cost_overheat: float = 3.0


func begin(us: UltimateSystem) -> void:
	var hk := us.combat.kit as HeatKit
	if hk:
		hk.set_overdrive(true, hook_cooldown)
	us.fx["aura_next"] = aura_interval


func tick(us: UltimateSystem, delta: float) -> void:
	us.fx["aura_next"] = float(us.fx.get("aura_next", aura_interval)) - delta
	if float(us.fx["aura_next"]) > 0.0 or aura_attack == null:
		return
	us.fx["aura_next"] = float(us.fx["aura_next"]) + aura_interval
	var m := us.combat.motor
	AreaBlast.explode(m, aura_attack, m.global_position + Vector3.UP * 2.0, aura_radius, 1.0, [], true)


func end(us: UltimateSystem) -> void:
	var hk := us.combat.kit as HeatKit
	if hk:
		hk.set_overdrive(false)


func begin_cost(us: UltimateSystem) -> void:
	var hk := us.combat.kit as HeatKit
	if hk:
		hk.overheat(cost_overheat, true)


func hud_active(_us: UltimateSystem) -> String:
	return "热量锁定 · 灼热常驻 · 钩爪冷却 %.0f s · 热浪 %.0f m" % [hook_cooldown, aura_radius]
