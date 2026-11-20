class_name UltimateDefinition
extends Resource
## Signature ultimate data. PALE SERAPH: 圣骸回响 · 冠冕补完 (RELIQUARY ECHO)
## uses the judgment fields below with `effect = null`. Phase 3b mechs set
## `effect` (HELLFANG 熔炉逆燃, VERDANT ARK 方舟苏生, AZURE ORACLE 终末坐标)
## and the windup rules. PROTOTYPE values (待测试).

@export var id: StringName = &"reliquary_echo"
@export var display_name: String = "圣骸回响 · 冠冕补完"
@export_range(0.0, 1.0) var hp_threshold: float = 0.3
@export var uses_per_match: int = 1

## Phase 3b: the ultimate's own behaviour (null = PALE SERAPH judgment).
@export var effect: UltimateEffect
## HUD / call-out wording for the active and cost phases.
@export var active_label: String = "审判"
@export var cost_label: String = "圣骸过载"
@export var cost_desc: String = "EN 不恢复"
## Screen-edge tint while our own ultimate is active.
@export var vignette_color: Color = Color(1.0, 0.85, 0.35, 0.7)

@export_group("Activation")
@export var windup: float = 0.35
## Frontal parryable hits during the windup are parried automatically.
@export var windup_parries: bool = true
## Rooted during the windup (no movement at all).
@export var windup_root: bool = false
## Windup super armour: hits do not stagger / interrupt it, except grabs
## and guard breaks (HELLFANG).
@export var windup_super_armor: bool = false
## Any landed hit interrupts the windup, even one that does not stagger
## (VERDANT ARK).
@export var windup_break_on_hit: bool = false
## Hard control during the active phase ends it early (AZURE beacon).
@export var active_ends_on_stagger: bool = false
## After a successful parry, pressing the ultimate within this time skips the windup.
@export var parry_activation_window: float = 0.5
## Interrupted windup: the ultimate is kept but locked for this long.
@export var interrupt_cooldown: float = 10.0

@export_group("Judgment state")
## Playtest R2-2: 6 → 10 s, plus offence / super armour / suppression field.
@export var duration: float = 10.0
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
## Outgoing damage multiplier for every attack started during judgment.
@export var damage_mult: float = 1.25
## Each melee (hitbox) attack also releases this forward shockwave
## (a short-range projectile) at the start of its active phase.
@export var wave_attack: AttackDefinition
## Super armour: clean hits dealing less than this do not stagger (the
## push is reduced). Grabs and guard breaks still do.
@export var armor_damage_threshold: float = 20.0
@export var armor_knockback_mult: float = 0.3

@export_group("Suppression field (圣域)")
## Hostile mechs within this radius get `field_status` refreshed every tick
## (slower, no EN regen, longer windups).
@export var field_radius: float = 12.0
@export var field_status: StatusEffectDefinition

@export_group("Overload (cost)")
@export var overload_duration: float = 3.0
@export var overload_damage_taken_mult: float = 1.3
@export var overload_blocks_en_regen: bool = true
