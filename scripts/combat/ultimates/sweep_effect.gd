class_name SweepEffect
extends UltimateEffect
## AZURE ORACLE 轨道扫射 (ORBITAL SWEEP, round 6; replaces 终末坐标). The
## oracle opens a direct uplink: an orbital beam lands where it is aimed
## (warning first) and sweeps the ground after its aim at a capped speed,
## burning a trail; at the end it collapses into one heavy strike. The
## oracle walks slowly and cannot use any other weapon meanwhile; a grab or
## a guard break cuts the uplink. Cost: cannon overheat. PROTOTYPE values.

@export var tick_attack: AttackDefinition
@export var collapse_attack: AttackDefinition
@export var burn_attack: AttackDefinition
@export var radius: float = 3.0
@export var speed: float = 12.0
@export var arm_time: float = 0.5
@export var tick_interval: float = 0.2
## Extra damage per mark stack on the victim (not consumed).
@export var mark_bonus: float = 0.1
@export var burn_every: float = 0.5
@export var burn_duration: float = 1.5
@export var burn_interval: float = 0.5
@export var sky_height: float = 45.0
@export var max_range: float = 60.0
@export var owner_speed_mult: float = 0.5
@export var unlocked_distance: float = 20.0

const MOD_UPLINK := &"sweep_uplink"


func begin(us: UltimateSystem) -> void:
	var c := us.combat
	var m := c.motor
	var mod := MovementModifier.create(MOD_UPLINK)
	mod.speed_mult = owner_speed_mult
	mod.block_dash = true
	m.add_modifier(mod)
	var mk := c.kit as MarkKit
	if mk:
		mk.sweeping = true
	var start := m.global_position + m.get_forward() * unlocked_distance
	if c.placement_set:
		start = c.placement_point
	else:
		var t := c.ranged_target()
		if t and is_instance_valid(t):
			start = t.global_position
	start = OrbitalStrike.clamp_to_range(m.global_position, start, max_range)
	var b := SweepBeam.new()
	m.get_parent().add_child(b)
	b.setup(c, self, start)
	us.fx["beam"] = b
	c.steering_def = tick_attack  # presentation: raised marking view, the player steers
	CombatEvents.kit_event.emit(m, &"sweep_start")


func end(us: UltimateSystem) -> void:
	var c := us.combat
	c.steering_def = null
	c.placement_set = false
	c.motor.remove_modifier(MOD_UPLINK)
	var mk := c.kit as MarkKit
	if mk:
		mk.sweeping = false
	var b: SweepBeam = us.fx.get("beam")
	if b and is_instance_valid(b):
		if collapse_attack and b.is_armed() and TeamRules.is_alive(c.motor):
			OrbitalStrike.call_at(c.motor, collapse_attack, b.global_position)
			CombatEvents.kit_event.emit(c.motor, &"sweep_collapse")
		b.remove()
	us.fx.erase("beam")


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
	var b: SweepBeam = us.fx.get("beam")
	if b == null or not is_instance_valid(b):
		return "轨道扫射"
	return "轨道扫射：%s · 光柱限速 %.0f m/s · 结束时坍缩" % ["转动视角引导光柱" if b.is_armed() else "落点预警", speed]
