class_name CombatProfile
extends Resource
## Per-mech combat data: HP, defence, reactions, kit. PROTOTYPE (待测试).

@export var display_name: String = "Combat"
@export var max_hp: float = 300.0

@export_group("Kit")
@export var light_combo: AttackDefinition
@export var skill: AttackDefinition
@export var ranged: AttackDefinition
@export var ultimate: UltimateDefinition
## X held past hold_threshold (X tap fires on release when this exists).
@export var skill_hold: AttackDefinition
## Left button held past hold_threshold; only while the kit allows it
## (otherwise the left button fires on press as usual).
@export var attack_hold: AttackDefinition
## Right button held = charge this attack, release = fire (replaces guard).
@export var charge_attack: AttackDefinition
## F performs this action instead of a parry (AZURE ORACLE backstep).
@export var defense_action: AttackDefinition
@export var hold_threshold: float = 0.3
## Mech resource system (heat / deployables / marks). Empty = none.
@export var kit: KitConfig

@export_group("Charge (charge_attack)")
@export var charge_time: float = 1.5
## Released below this charge fraction = cancelled, nothing fired.
@export_range(0.0, 1.0) var charge_min: float = 0.25
@export var charge_speed_mult: float = 0.35

@export_group("Guard")
## Total frontal arc covered by guard AND parry (deg).
@export var guard_arc_deg: float = 120.0
@export_range(0.0, 1.0) var guard_damage_taken: float = 0.25
@export var guard_speed_mult: float = 0.5
## EN drained per point of damage blocked; guard breaks when EN runs out.
@export var guard_en_per_damage: float = 0.45
@export var guard_break_stagger: float = 0.8

@export_group("Parry (mirror shield)")
@export var parry_window: float = 0.15
## Recovery after a whiffed parry: no defence, extra damage taken.
@export var parry_whiff_recovery: float = 0.4
@export var parry_whiff_damage_mult: float = 1.2
@export var parry_hitstop: float = 0.1
## Melee attacker knocked off-balance by a parry.
@export var offbalance_time: float = 0.6
@export var offbalance_knockback: float = 7.0
## Damage multiplier for the parrier's hits on an off-balance victim.
@export var counter_damage_mult: float = 1.5
## Dedicated counter (PALE SERAPH 反刺): pressing attack while the parried
## melee attacker is still off-balance starts this attack aimed at them
## (lunges in, unguardable). The counter multiplier above still applies.
## null = no riposte (HELLFANG / VERDANT parries do not cause off-balance).
@export var parry_riposte: AttackDefinition
## false: a parried melee attacker is only pushed back (interrupted), not
## knocked off-balance, and there is no counter bonus (HELLFANG / VERDANT).
@export var parry_causes_offbalance: bool = true
## Reflected projectile: damage and speed multipliers.
@export var reflect_damage_mult: float = 0.8
@export var reflect_speed_mult: float = 1.2

@export_group("Hard-control protection")
## Window in which hard controls (stagger / off-balance / guard break) count.
@export var cc_window: float = 4.0
## Each previous CC in the window scales the next duration by this factor.
@export var cc_decay: float = 0.7
## After this many CCs in the window the mech becomes CC-immune.
@export var cc_immunity_after: int = 3
@export var cc_immunity_time: float = 1.5
