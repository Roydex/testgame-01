class_name UltimateSystem
extends Node
## Generic low-HP signature ultimate runner (data: UltimateDefinition).
## PALE SERAPH: 圣骸回响 · 冠冕补完 — the relic's dormant guardian protocol
## wakes at critical damage, the broken crown completes and the light wings
## unfold into a short JUDGMENT state, followed by an OVERLOAD cost.
##
## Phases: LOCKED → READY (HP ≤ threshold) → WINDUP → JUDGMENT → OVERLOAD →
## SPENT (or READY again if uses remain). An interrupted windup keeps the
## ultimate but locks it for interrupt_cooldown (COOLDOWN).

enum Phase { LOCKED, READY, WINDUP, JUDGMENT, OVERLOAD, SPENT, COOLDOWN }
const PHASE_NAMES := ["LOCKED", "READY", "WINDUP", "JUDGMENT", "OVERLOAD", "SPENT", "COOLDOWN"]
const MOD_JUDGMENT := &"ult_judgment"
const MOD_OVERLOAD := &"ult_overload"

var definition: UltimateDefinition
var combat: CombatStateMachine
var phase: int = Phase.LOCKED
var phase_time_left: float = 0.0
var uses_left: int = 1
var spear_charges_left: int = 0
## Practice mode: uses are not consumed.
var unlimited_uses: bool = false


func setup(def: UltimateDefinition, p_combat: CombatStateMachine) -> void:
	definition = def
	combat = p_combat
	uses_left = def.uses_per_match
	process_physics_priority = -4


func get_phase_name() -> String:
	return PHASE_NAMES[phase]


func in_judgment() -> bool:
	return phase == Phase.JUDGMENT


func is_ready() -> bool:
	return phase == Phase.READY


func parry_window_mult() -> float:
	return definition.parry_window_mult if phase == Phase.JUDGMENT else 1.0


func damage_taken_mult() -> float:
	return definition.overload_damage_taken_mult if phase == Phase.OVERLOAD else 1.0


func outgoing_mult() -> float:
	return definition.damage_mult if phase == Phase.JUDGMENT else 1.0


## Judgment super armour: does a clean hit of `damage` stagger us?
func armor_absorbs(hit: HitInfo) -> bool:
	return phase == Phase.JUDGMENT and hit.final_damage < definition.armor_damage_threshold \
		and not hit.attack.guard_break and not hit.force_guard_break


## Suppression field: refresh the status on hostile mechs inside the radius.
func _tick_field() -> void:
	if definition.field_status == null or definition.field_radius <= 0.0:
		return
	var c := combat.motor.global_position
	for t in TeamRules.get_valid_targets(combat.motor, &"mechs"):
		if t.global_position.distance_to(c) > definition.field_radius:
			continue
		var tc := DamageSystem.get_combat(t)
		if tc:
			tc.status.apply(definition.field_status, combat.motor)


func _unlock_condition() -> bool:
	return uses_left > 0 and combat.health != null and combat.health.ratio() <= definition.hp_threshold


func _physics_process(delta: float) -> void:
	if combat == null or combat.motor.in_hitstop() or combat.is_dead():
		return
	match phase:
		Phase.LOCKED:
			if _unlock_condition():
				_set_phase(Phase.READY)
		Phase.COOLDOWN:
			phase_time_left -= delta
			if phase_time_left <= 0.0:
				_set_phase(Phase.READY if _unlock_condition() else Phase.LOCKED)
		Phase.JUDGMENT:
			phase_time_left -= delta
			_tick_field()
			if phase_time_left <= 0.0:
				_end_judgment()
		Phase.OVERLOAD:
			phase_time_left -= delta
			if phase_time_left <= 0.0:
				combat.motor.remove_modifier(MOD_OVERLOAD)
				_set_phase(Phase.READY if _unlock_condition() else (Phase.SPENT if uses_left <= 0 else Phase.LOCKED))


## Ultimate button. Within parry_activation_window after a successful parry
## it activates instantly; otherwise it starts the (parrying) windup.
func try_activate() -> bool:
	if phase != Phase.READY:
		return false
	if combat.time - combat.last_parry_time <= definition.parry_activation_window:
		enter_judgment()
		return true
	_set_phase(Phase.WINDUP)
	combat.start_ult_windup(definition.windup)
	return true


func enter_judgment() -> void:
	if phase == Phase.JUDGMENT or uses_left <= 0:
		return
	if not unlimited_uses:
		uses_left -= 1
	spear_charges_left = definition.spear_charges
	phase_time_left = definition.duration
	var m := MovementModifier.create(MOD_JUDGMENT)
	m.speed_mult = definition.speed_mult
	m.en_cost_mult = definition.dash_cost_mult
	combat.motor.add_modifier(m)
	_set_phase(Phase.JUDGMENT)


func _end_judgment() -> void:
	combat.motor.remove_modifier(MOD_JUDGMENT)
	spear_charges_left = 0
	var m := MovementModifier.create(MOD_OVERLOAD)
	m.block_en_regen = definition.overload_blocks_en_regen
	combat.motor.add_modifier(m)
	phase_time_left = definition.overload_duration
	_set_phase(Phase.OVERLOAD)


func on_windup_interrupted() -> void:
	if phase == Phase.WINDUP:
		phase_time_left = definition.interrupt_cooldown
		_set_phase(Phase.COOLDOWN)


## Practice reset: back to the start-of-match state.
func reset() -> void:
	combat.motor.remove_modifier(MOD_JUDGMENT)
	combat.motor.remove_modifier(MOD_OVERLOAD)
	uses_left = definition.uses_per_match
	spear_charges_left = 0
	phase_time_left = 0.0
	_set_phase(Phase.LOCKED)


func on_owner_died() -> void:
	combat.motor.remove_modifier(MOD_JUDGMENT)
	combat.motor.remove_modifier(MOD_OVERLOAD)
	_set_phase(Phase.SPENT)


func _set_phase(p: int) -> void:
	if p == phase:
		return
	phase = p
	CombatEvents.ultimate_phase.emit(combat.motor, PHASE_NAMES[p])
