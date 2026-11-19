class_name HeatKit
extends MechKit
## HELLFANG 熔炉热量. Heavy swings, the grapple, the ram and dashes build
## heat; it cools slowly when idle (slower while guarding). Above the
## scorching threshold every attack hits harder. At max heat the furnace
## OVERHEATS: forced venting — no attacks, no dashes, slower, takes more
## damage. Active vent (X held) cools safely but is a visible, slow action.

const MOD_OVERHEAT := &"heat_overheat"

var heat: float = 0.0
var overheat_left: float = 0.0
var _since_gain := 0.0


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
	heat = cfg().max_heat
	overheat_left = maxf(overheat_left, duration)
	var m := MovementModifier.create(MOD_OVERHEAT)
	m.block_dash = true
	m.speed_mult = cfg().overheat_speed_mult
	motor.add_modifier(m)
	CombatEvents.kit_event.emit(motor, &"overheat")


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


func on_guarded(hit: HitInfo) -> void:
	add_heat(hit.attack.damage * hit.damage_mult * cfg().guard_heat_per_damage)


func reset() -> void:
	heat = 0.0
	overheat_left = 0.0
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
		return "热量 过热！强制排气 %.1f s（不能攻击 / 冲刺，受伤 ×%.1f）" % [overheat_left, cfg().overheat_damage_taken]
	return "热量 %3.0f / %.0f%s" % [heat, cfg().max_heat, "  灼热（伤害 ×%.1f）" % cfg().scorch_damage_mult if is_scorching() else ""]


func hud_bar() -> float:
	return heat / cfg().max_heat
