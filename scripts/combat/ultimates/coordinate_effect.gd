class_name CoordinateEffect
extends UltimateEffect
## AZURE ORACLE 终末坐标 (FINAL COORDINATE). The oracle roots itself as a
## beacon: every `interval` s each marked enemy in range gets a small orbital
## strike (full, dodgeable telegraph; shelters block it); pulse hits mark
## twice as fast. Hard control on the beacon ends it early. Cost: the cannon
## overheats (no shooting, backstep on cooldown). PROTOTYPE values (待测试).

@export var strike_attack: AttackDefinition
@export var interval: float = 1.2
@export var first_delay: float = 0.3
@export var max_range: float = 60.0

const MOD_BEACON := &"coordinate_beacon"


func begin(us: UltimateSystem) -> void:
	var mod := MovementModifier.create(MOD_BEACON)
	mod.forced = true  # pinned in place, on the ground or mid-air
	mod.forced_velocity = Vector3.ZERO
	mod.block_dash = true
	mod.block_jump = true
	us.combat.motor.add_modifier(mod)
	var mk := us.combat.kit as MarkKit
	if mk:
		mk.double_marks = true
	us.fx["next"] = first_delay
	us.fx["calls"] = 0


func tick(us: UltimateSystem, delta: float) -> void:
	us.fx["next"] = float(us.fx.get("next", interval)) - delta
	if float(us.fx["next"]) > 0.0 or strike_attack == null:
		return
	us.fx["next"] = float(us.fx["next"]) + interval
	var m := us.combat.motor
	for t in marked_targets(us):
		OrbitalStrike.call_on(us.combat, strike_attack, t)
		us.fx["calls"] = int(us.fx.get("calls", 0)) + 1
	CombatEvents.kit_event.emit(m, &"coordinate_call")


## Hostile mechs in range carrying at least one mark.
func marked_targets(us: UltimateSystem) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var m := us.combat.motor
	for t in TeamRules.get_valid_targets(m, &"mechs"):
		var tc := DamageSystem.get_combat(t)
		if tc and tc.status.stacks(&"mark") > 0 and m.global_position.distance_to(t.global_position) <= max_range:
			out.append(t)
	return out


func end(us: UltimateSystem) -> void:
	us.combat.motor.remove_modifier(MOD_BEACON)
	var mk := us.combat.kit as MarkKit
	if mk:
		mk.double_marks = false


func begin_cost(us: UltimateSystem) -> void:
	var mk := us.combat.kit as MarkKit
	if mk:
		mk.cannon_overheat = true
	var bs := us.combat.profile.defense_action
	if bs:
		us.combat.set_cooldown(bs.id, bs.cooldown)


func end_cost(us: UltimateSystem) -> void:
	var mk := us.combat.kit as MarkKit
	if mk:
		mk.cannon_overheat = false


func hud_active(us: UltimateSystem) -> String:
	return "信标（不能移动）· 已标记 %d 个目标 · 下次打击 %.1f s" % [marked_targets(us).size(), maxf(float(us.fx.get("next", 0.0)), 0.0)]
