class_name CombatStateMachine
extends Node
## Combat / hit-reaction layer, independent from the motion layer.
## Prototype scope: only the plumbing (no real attacks). It influences
## movement exclusively through MovementModifier + MechMotor.apply_impulse,
## never by writing motor velocity. It can never block ALL control: even
## STAGGER keeps gravity, active descent and camera / lock control alive.

signal combat_state_changed(old_state: int, new_state: int)

enum CombatState { READY, ACTION, STAGGER }
const STATE_NAMES := ["READY", "ACTION", "STAGGER"]

const MOD_ACTION := &"combat_action"
const MOD_STAGGER := &"combat_stagger"

@export var motor_path: NodePath = ^".."

var state: int = CombatState.READY
var state_timer: float = 0.0
var motor: MechMotor


func _ready() -> void:
	motor = get_node_or_null(motor_path) as MechMotor


func get_state_name() -> String:
	return STATE_NAMES[state]


## Generic action placeholder (future skills): slows movement and blocks dash
## for `duration`, but movement input stays live.
func start_action(duration: float, speed_mult: float = 0.4, block_thrust: bool = false) -> bool:
	if state == CombatState.STAGGER:
		return false
	var m := MovementModifier.create(MOD_ACTION, duration)
	m.speed_mult = speed_mult
	m.block_dash = true
	m.block_jump = true
	m.block_thrust = block_thrust
	m.turn_mult = 0.5
	motor.add_modifier(m)
	_enter(CombatState.ACTION, duration)
	return true


## Hit reaction: blocks steering and thrust (the mech falls if airborne),
## pushes the mech with an impulse.
func apply_stagger(duration: float, knockback: Vector3 = Vector3.ZERO) -> void:
	motor.remove_modifier(MOD_ACTION)
	var m := MovementModifier.create(MOD_STAGGER, duration)
	m.block_move = true
	m.block_dash = true
	m.block_jump = true
	m.block_thrust = true
	m.block_facing = true
	motor.add_modifier(m)
	if knockback != Vector3.ZERO:
		motor.apply_impulse(knockback)
	_enter(CombatState.STAGGER, duration)


func _physics_process(delta: float) -> void:
	if state == CombatState.READY:
		return
	state_timer -= delta
	if state_timer <= 0.0:
		_enter(CombatState.READY, 0.0)


func _enter(s: int, duration: float) -> void:
	var old := state
	state = s
	state_timer = duration
	if old != s:
		combat_state_changed.emit(old, s)
