class_name MechKit
extends Node
## Per-mech resource and rule component (heat / deployables / marks).
## CombatStateMachine calls these hooks at fixed seams; a kit never writes
## velocity and only touches movement through MovementModifier, exactly like
## the combat layer. The base class is the neutral kit (PALE SERAPH).

var combat: CombatStateMachine
var motor: MechMotor
var config: KitConfig


func setup(p_combat: CombatStateMachine, p_config: KitConfig) -> void:
	combat = p_combat
	motor = p_combat.motor
	config = p_config
	name = "Kit"
	process_physics_priority = -4


## May `def` start now (resource requirements)?
func can_start(_def: AttackDefinition) -> bool:
	return true


## Damage multiplier for an attack this mech starts (fixed at start).
func outgoing_mult(_def: AttackDefinition) -> float:
	return 1.0


## Multiplier on clean-hit damage this mech takes.
func incoming_mult(_hit: HitInfo) -> float:
	return 1.0


## Added to the guard damage ratio while guarding (negative = tougher).
func guard_ratio_add() -> float:
	return 0.0


func blocks_actions() -> bool:
	return false


func on_attack_started(_def: AttackDefinition) -> void:
	pass


func on_attack_active(_def: AttackDefinition) -> void:
	pass


## The attack ended; `landed` = at least one HIT / GUARDED / GUARD_BREAK.
func on_attack_finished(_def: AttackDefinition, _landed: bool) -> void:
	pass


## A hit we dealt was resolved (any delivery, including projectiles).
func on_hit_dealt(_hit: HitInfo) -> void:
	pass


## We blocked a hit with our guard.
func on_guarded(_hit: HitInfo) -> void:
	pass


## Lunge tuning for an attack (HELLFANG bite): speed multiplier and extra
## steering (deg/s) toward the current aim target.
func lunge_speed_mult(_def: AttackDefinition) -> float:
	return 1.0


func lunge_steer_bonus(_def: AttackDefinition) -> float:
	return 0.0


## Guard (right button) just started / was released by the player.
func on_guard_started() -> void:
	pass


func on_guard_released() -> void:
	pass


func reset() -> void:
	pass


## Short HUD line, e.g. "热量 72 / 100  灼热".
func hud_text() -> String:
	return ""


## 0..1 bar value for the HUD (or -1 = no bar).
func hud_bar() -> float:
	return -1.0
