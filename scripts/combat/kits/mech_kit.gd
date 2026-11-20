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


## We blocked a hit with our guard (called before the guard holds or breaks).
func on_guarded(_hit: HitInfo) -> void:
	pass


## The guard held against `hit` (GUARDED, not broken): mirror refraction.
func on_guard_held(_hit: HitInfo) -> void:
	pass


## A guard-breaking `hit` does not break our guard (PALE SERAPH mirror vs
## beams: light is what the mirror is made for).
func resists_guard_break(_hit: HitInfo) -> bool:
	return false


## May our guard (parry = false) or parry (parry = true) stop `hit` at all?
## false: the hit goes through as a clean hit (PALE SERAPH overheated mirror,
## ultimate attacks outside judgment).
func defends_against(_hit: HitInfo, _parry: bool) -> bool:
	return true


## A parry of ours succeeded (first parried melee attacker, or a swallowed
## projectile when the profile does not reflect).
func on_parry_success(_hit: HitInfo, _projectile: bool) -> void:
	pass


## `def` was cut short in its windup and converted into another attack
## (HELLFANG first swing → ram): refund what it cost.
func on_attack_converted(_def: AttackDefinition) -> void:
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
