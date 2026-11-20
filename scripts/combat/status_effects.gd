class_name StatusEffects
extends Node
## Timed statuses on one combatant. Movement effects are applied through a
## single MovementModifier ("status_effects"); damage effects are read by
## DamageSystem. Hard control (stagger / off-balance) is NOT a status: it
## stays in CombatStateMachine with its diminishing returns.

const MOD_ID := &"status_effects"

var motor: MechMotor
## id → {def, stacks, left, source}
var _active: Dictionary = {}


func setup(p_motor: MechMotor) -> void:
	motor = p_motor
	name = "StatusEffects"


func apply(def: StatusEffectDefinition, source: Node3D = null, stacks: int = 1) -> void:
	if def == null:
		return
	var e: Dictionary = _active.get(def.id, {})
	if e.is_empty():
		e = {"def": def, "stacks": 0, "left": def.duration, "source": source}
		_active[def.id] = e
	e.stacks = mini(int(e.stacks) + stacks, def.max_stacks)
	if def.refresh_on_apply or float(e.left) <= 0.0:
		e.left = def.duration
	e.source = source
	_refresh_mod()
	CombatEvents.status_changed.emit(motor, def.id, int(e.stacks))


func stacks(id: StringName) -> int:
	var e: Dictionary = _active.get(id, {})
	return int(e.stacks) if not e.is_empty() else 0


func has(id: StringName) -> bool:
	return _active.has(id)


func time_left(id: StringName) -> float:
	var e: Dictionary = _active.get(id, {})
	return float(e.left) if not e.is_empty() else 0.0


## Removes `n` stacks (all when n < 0). Returns how many were removed.
func consume(id: StringName, n: int = -1) -> int:
	var e: Dictionary = _active.get(id, {})
	if e.is_empty():
		return 0
	var had := int(e.stacks)
	var take := had if n < 0 else mini(n, had)
	e.stacks = had - take
	if int(e.stacks) <= 0:
		_active.erase(id)
	_refresh_mod()
	CombatEvents.status_changed.emit(motor, id, stacks(id))
	return take


func clear() -> void:
	var ids := _active.keys()
	_active.clear()
	_refresh_mod()
	for id in ids:
		CombatEvents.status_changed.emit(motor, id, 0)


func damage_taken_mult() -> float:
	var m := 1.0
	for e: Dictionary in _active.values():
		m *= (e.def as StatusEffectDefinition).damage_taken_mult
	return m


func guard_ratio_add() -> float:
	var a := 0.0
	for e: Dictionary in _active.values():
		a += (e.def as StatusEffectDefinition).guard_damage_taken_add
	return a


func windup_mult() -> float:
	var m := 1.0
	for e: Dictionary in _active.values():
		m *= (e.def as StatusEffectDefinition).windup_mult
	return m


func get_ids() -> Array:
	return _active.keys()


func _physics_process(delta: float) -> void:
	if _active.is_empty() or motor == null or motor.in_hitstop():
		return
	var expired: Array = []
	for id in _active:
		var e: Dictionary = _active[id]
		e.left = float(e.left) - delta
		if float(e.left) <= 0.0:
			expired.append(id)
	for id in expired:
		_active.erase(id)
		CombatEvents.status_changed.emit(motor, id, 0)
	if not expired.is_empty():
		_refresh_mod()


func _refresh_mod() -> void:
	if motor == null:
		return
	var speed := 1.0
	var en_cost := 1.0
	var no_dash := false
	var no_regen := false
	for e: Dictionary in _active.values():
		var d := e.def as StatusEffectDefinition
		speed *= d.speed_mult
		en_cost *= d.en_cost_mult
		no_dash = no_dash or d.block_dash
		no_regen = no_regen or d.block_en_regen
	if is_equal_approx(speed, 1.0) and is_equal_approx(en_cost, 1.0) and not no_dash and not no_regen:
		motor.remove_modifier(MOD_ID)
		return
	var m := MovementModifier.create(MOD_ID)
	m.speed_mult = speed
	m.en_cost_mult = en_cost
	m.block_dash = no_dash
	m.block_en_regen = no_regen
	motor.add_modifier(m)
