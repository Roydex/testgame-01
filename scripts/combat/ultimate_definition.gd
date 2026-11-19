class_name UltimateDefinition
extends Resource
## Signature ultimate data. PALE SERAPH: 圣骸回响 · 冠冕补完 (RELIQUARY ECHO).
## PROTOTYPE values (待测试).

@export var id: StringName = &"reliquary_echo"
@export var display_name: String = "圣骸回响 · 冠冕补完"
@export_range(0.0, 1.0) var hp_threshold: float = 0.3
@export var uses_per_match: int = 1

@export_group("Activation")
@export var windup: float = 0.35
## Frontal parryable hits during the windup are parried automatically.
@export var windup_parries: bool = true
## After a successful parry, pressing the ultimate within this time skips the windup.
@export var parry_activation_window: float = 0.5
## Interrupted windup: the ultimate is kept but locked for this long.
@export var interrupt_cooldown: float = 10.0

@export_group("Judgment state")
@export var duration: float = 6.0
@export var parry_window_mult: float = 2.0
@export var speed_mult: float = 1.25
@export var dash_cost_mult: float = 0.5
## Auto counter after a melee parry during judgment.
@export var judgment_counter: AttackDefinition
## Replaces the skill during judgment.
@export var final_spear: AttackDefinition
@export var spear_charges: int = 2
@export var reflect_damage_mult: float = 1.5
@export var reflect_speed_mult: float = 1.5
## Horizontal homing of reflected projectiles (deg/s).
@export var reflect_homing_deg: float = 25.0

@export_group("Overload (cost)")
@export var overload_duration: float = 3.0
@export var overload_damage_taken_mult: float = 1.3
@export var overload_blocks_en_regen: bool = true
