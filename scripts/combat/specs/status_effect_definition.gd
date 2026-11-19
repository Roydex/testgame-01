class_name StatusEffectDefinition
extends Resource
## A timed status applied by a hit or an area (slow, armor break, mark…).
## Movement effects go through a MovementModifier owned by StatusEffects;
## damage effects are read by DamageSystem. PROTOTYPE values (待测试).

@export var id: StringName = &"status"
@export var display_name: String = "Status"
@export var duration: float = 3.0
@export var max_stacks: int = 1
## Re-applying refreshes the duration (and adds a stack up to max_stacks).
@export var refresh_on_apply: bool = true

@export_group("Movement (via MovementModifier)")
@export var speed_mult: float = 1.0
@export var en_cost_mult: float = 1.0
@export var block_dash: bool = false

@export_group("Damage")
## Multiplies damage this mech takes on clean hits (armor break > 1).
@export var damage_taken_mult: float = 1.0
## Added to the victim's guard damage ratio (armor break weakens guards).
@export var guard_damage_taken_add: float = 0.0

@export_group("Presentation")
@export var color: Color = Color(1, 1, 1)
