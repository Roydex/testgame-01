class_name HeatKit
extends MechKit
## HELLFANG 熔炉热量. Heavy swings, the grapple, the ram and dashes build
## heat; it cools slowly when idle (slower while guarding). Above the
## scorching threshold every attack hits harder. At max heat the furnace
## OVERHEATS: forced venting — no attacks, no dashes, slower, takes more
## damage. Active vent (X held) cools safely but is a visible, slow action.

const MOD_OVERHEAT := &"heat_overheat"
const MOD_BITE := &"heat_bite"

var heat: float = 0.0
var overheat_left: float = 0.0
var _since_gain := 0.0
## 熔炉格挡: damage blocked during the current guard.
var absorbed: float = 0.0
## 步进咬合: the mech our last axe swing connected with.
var bite_target: MechMotor


func cfg() -> HeatConfig:
	return config as HeatConfig


func setup(p_combat: CombatStateMachine, p_config: KitConfig) -> void:
	super.setup(p_combat, p_config if p_config else HeatConfig.new())
	motor.dashed.connect(func(_air: bool) -> void: add_heat(cfg().heat_per_dash))


func is_overheated() -> bool:
	return overheat_left > 0.0


func is_scorching() -> bool:
	return heat >= cfg().scorch_threshold and not is_overheated()


func add_heat(v: float) -> void:
	if v <= 0.0 or is_overheated():
		return
	heat = minf(heat + v, cfg().max_heat)
	_since_gain = 0.0
	if heat >= cfg().max_heat:
		overheat(cfg().overheat_duration)


func overheat(duration: float) -> void:
	var fresh := not is_overheated()
	heat = cfg().max_heat
	overheat_left = maxf(overheat_left, duration)
	var m := MovementModifier.create(MOD_OVERHEAT)
	m.block_dash = cfg().overheat_blocks_dash
	m.speed_mult = cfg().overheat_speed_mult
	motor.add_modifier(m)
	CombatEvents.kit_event.emit(motor, &"overheat")
	if fresh:
		_vent_steam()


## Entering overheat vents a steam ring: hostile mechs nearby are pushed
## away (no damage), buying the furnace room to cool. Cover blocks it.
func _vent_steam() -> void:
	var c := motor.global_position + Vector3.UP * 2.0
	for t in TeamRules.get_valid_targets(motor, &"mechs"):
		var tm := t as MechMotor
		if tm == null:
			continue
		var p := tm.global_position + Vector3.UP * 2.0
		if c.distance_to(p) > cfg().steam_radius or not CombatTypes.has_line_of_sight(motor.get_world_3d(), c, p):
			continue
		var push := tm.global_position - motor.global_position
		push.y = 0.0
		tm.apply_impulse(push.normalized() * cfg().steam_push + Vector3.UP * 2.0)
	CombatEvents.area_telegraph.emit(motor, motor.global_position + Vector3.UP * 1.0, cfg().steam_radius, 0.0, &"steam")


func blocks_actions() -> bool:
	return is_overheated()


func can_start(def: AttackDefinition) -> bool:
	if is_overheated():
		return false
	if def.min_heat > 0.0 and heat < def.min_heat:
		return false
	if def.heat_vent_rate > 0.0 and heat <= 1.0:
		return false
	return true


func outgoing_mult(def: AttackDefinition) -> float:
	if def.heat_vent_rate > 0.0:
		return 1.0
	return cfg().scorch_damage_mult if is_scorching() else 1.0


func incoming_mult(_hit: HitInfo) -> float:
	return cfg().overheat_damage_taken if is_overheated() else 1.0


func on_attack_started(def: AttackDefinition) -> void:
	add_heat(def.heat_cost)
	if def.heat_vent_rate > 0.0:
		CombatEvents.kit_event.emit(motor, &"vent")


func on_attack_finished(def: AttackDefinition, landed: bool) -> void:
	if def.whiff_overheats and not landed and not is_overheated():
		overheat(cfg().whiff_overheat_duration)


func on_hit_dealt(hit: HitInfo) -> void:
	if DamageSystem.is_landed(hit.result):
		add_heat(hit.attack.heat_on_hit)
		if hit.attack.attack_type == CombatTypes.AttackType.MELEE and hit.attack.get_delivery() == CombatTypes.Delivery.HITBOX \
				and hit.victim is MechMotor:
			_bite(hit.victim as MechMotor)


## 步进咬合: mark the victim and home our dashes onto it while it lasts.
func _bite(victim: MechMotor) -> void:
	var st := cfg().bite_status
	if st == null:
		return
	var vc := DamageSystem.get_combat(victim)
	if vc == null:
		return
	vc.status.apply(st, motor)
	bite_target = victim
	var m := MovementModifier.create(MOD_BITE, st.duration)
	m.dash_home_target = victim
	m.dash_home_range = cfg().bite_dash_home_range
	m.dash_home_angle_deg = cfg().bite_dash_home_angle_deg
	motor.add_modifier(m)
	CombatEvents.kit_event.emit(motor, &"bite")


func bite_active() -> bool:
	if bite_target == null or not is_instance_valid(bite_target) or not TeamRules.is_alive(bite_target):
		return false
	var vc := DamageSystem.get_combat(bite_target)
	return vc != null and cfg().bite_status != null and vc.status.has(cfg().bite_status.id)


func _bites(def: AttackDefinition) -> bool:
	return def.attack_type == CombatTypes.AttackType.MELEE and bite_active() and combat.aim_target == bite_target


func lunge_speed_mult(def: AttackDefinition) -> float:
	return cfg().bite_lunge_mult if _bites(def) else 1.0


func lunge_steer_bonus(def: AttackDefinition) -> float:
	return cfg().bite_steer_bonus_deg if _bites(def) else 0.0


func on_guarded(hit: HitInfo) -> void:
	var dmg := hit.attack.damage * hit.damage_mult
	add_heat(dmg * cfg().guard_heat_per_damage)
	absorbed += dmg
	CombatEvents.kit_event.emit(motor, &"furnace_absorb")


func on_guard_started() -> void:
	absorbed = 0.0


## Releasing the guard after soaking enough damage vents it as a blast.
func on_guard_released() -> void:
	var c := cfg()
	var a := minf(absorbed, c.furnace_absorb_cap)
	absorbed = 0.0
	if c.furnace_burst == null or a < c.furnace_min_absorbed or is_overheated():
		return
	var dmg := c.furnace_burst.damage + a * c.furnace_damage_per_absorbed
	if combat.start_kit_attack(c.furnace_burst, dmg / maxf(c.furnace_burst.damage, 0.01)):
		CombatEvents.kit_event.emit(motor, &"furnace_burst")


func reset() -> void:
	heat = 0.0
	overheat_left = 0.0
	absorbed = 0.0
	bite_target = null
	motor.remove_modifier(MOD_BITE)
	motor.remove_modifier(MOD_OVERHEAT)


func _physics_process(delta: float) -> void:
	if combat == null or motor.in_hitstop() or combat.is_dead():
		return
	if is_overheated():
		overheat_left -= delta
		heat = cfg().max_heat * clampf(overheat_left / cfg().overheat_duration, 0.0, 1.0) + cfg().overheat_reset * (1.0 - clampf(overheat_left / cfg().overheat_duration, 0.0, 1.0))
		if overheat_left <= 0.0:
			overheat_left = 0.0
			heat = cfg().overheat_reset
			motor.remove_modifier(MOD_OVERHEAT)
			CombatEvents.kit_event.emit(motor, &"overheat_end")
		return
	_since_gain += delta
	var a := combat.attack
	if a and a.heat_vent_rate > 0.0 and combat.get_attack_phase() == 1:
		heat = maxf(heat - a.heat_vent_rate * delta, 0.0)
	elif _since_gain >= cfg().decay_delay:
		var r := cfg().decay_per_sec * (cfg().guard_decay_mult if combat.is_guarding() else 1.0)
		heat = maxf(heat - r * delta, 0.0)


func hud_text() -> String:
	if is_overheated():
		return "热量 过热！强制排气 %.1f s（不能攻击%s，受伤 ×%.2f）" % [overheat_left, " / 冲刺" if cfg().overheat_blocks_dash else "，可以冲刺", cfg().overheat_damage_taken]
	var line := "热量 %3.0f / %.0f%s" % [heat, cfg().max_heat, "  灼热（伤害 ×%.1f）" % cfg().scorch_damage_mult if is_scorching() else ""]
	if bite_active():
		line += "  咬住 %.1fs" % DamageSystem.get_combat(bite_target).status.time_left(cfg().bite_status.id)
	if combat.is_guarding() and absorbed > 0.0:
		var ready := minf(absorbed, cfg().furnace_absorb_cap) >= cfg().furnace_min_absorbed
		line += "  熔炉吸收 %.0f%s" % [absorbed, "（松开右键：爆燃反震）" if ready else ""]
	return line


func hud_bar() -> float:
	return heat / cfg().max_heat
