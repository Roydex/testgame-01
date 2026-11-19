class_name MechCommand
extends RefCounted
## One frame of movement intent. Produced by PlayerBrain / AIBrain / test
## scripts and consumed by MechMotor. Brains never touch velocity directly.

## Desired horizontal move direction in world space (y ignored, length <= 1).
var move: Vector3 = Vector3.ZERO
## Held: thrust upward (jump on the ground when newly pressed).
var ascend: bool = false
## Held: active descent while airborne.
var descend: bool = false
## Edge: jump requested this frame.
var jump_pressed: bool = false
## Edge: dash requested this frame.
var dash_pressed: bool = false
## Desired facing (world, horizontal). ZERO = face movement direction.
var face_dir: Vector3 = Vector3.ZERO

# --- combat intent (consumed by CombatStateMachine, ignored by the motor)
var attack_pressed: bool = false
var skill_pressed: bool = false
var parry_pressed: bool = false
var ult_pressed: bool = false
## Held.
var guard_held: bool = false
var attack_held: bool = false
var skill_held: bool = false


func clear_edges() -> void:
	jump_pressed = false
	dash_pressed = false
	attack_pressed = false
	skill_pressed = false
	parry_pressed = false
	ult_pressed = false


func copy_from(other: MechCommand) -> void:
	move = other.move
	ascend = other.ascend
	descend = other.descend
	jump_pressed = other.jump_pressed
	dash_pressed = other.dash_pressed
	face_dir = other.face_dir
	attack_pressed = other.attack_pressed
	skill_pressed = other.skill_pressed
	parry_pressed = other.parry_pressed
	ult_pressed = other.ult_pressed
	guard_held = other.guard_held
	attack_held = other.attack_held
	skill_held = other.skill_held
