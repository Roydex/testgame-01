class_name MirrorConfig
extends KitConfig
## PALE SERAPH 流光镜盾 (round 6, user design 2026-11-20). The right-button
## guard no longer drains EN: blocked damage heats the mirror instead; it
## cools while nothing is blocked. At max heat the mirror overheats — the
## pose can still be held but it neither reduces damage nor refracts until
## it has cooled back to zero. Blocked projectiles refract back toward the
## shooter; blocked beams shoot a light ray toward the crosshair. Ultimate
## attacks pass straight through the mirror outside judgment; in judgment it
## stops them and heats half as fast. PROTOTYPE values (待测试).

@export var max_heat: float = 100.0
## Heat per point of raw damage blocked (beams × beam_heat_mult).
@export var heat_per_damage: float = 0.8
@export var beam_heat_mult: float = 1.5
## Cooling (per s) after `cool_delay` s without blocking anything.
@export var cool_delay: float = 0.6
@export var cool_per_sec: float = 20.0
## Cooling while overheated; the mirror works again once heat reaches 0.
@export var overheat_cool_per_sec: float = 40.0
## Heat gain multiplier in judgment (耐热翻倍).
@export var judgment_heat_mult: float = 0.5
@export_group("Refraction")
## Damage multiplier of a guard-refracted projectile (the F parry keeps
## CombatProfile.reflect_damage_mult).
@export var projectile_refract_mult: float = 0.4
## Reflected light: fraction of the blocked beam's damage, range, attack.
@export var beam_reflect_mult: float = 0.4
@export var ray_range: float = 60.0
@export var ray_attack: AttackDefinition


func create_kit() -> MechKit:
	return MirrorKit.new()
