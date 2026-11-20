class_name OrbitalSpec
extends Resource
## Delayed orbital strike (AZURE ORACLE 轨道激光). A ground circle appears
## under the target, FOLLOWS it for `follow_time` (+ `follow_per_mark` per
## mark stack) at most `follow_speed` (a dash outruns it; orange), then LOCKS
## in place for `lock_time` (red), then a vertical BEAM hits everything inside
## whose line to the sky is clear: roofs block it. Total telegraph =
## follow + lock. Playtest feedback 2026-11-19: the old fixed 1.2 s circle was
## escaped by walking two steps. PROTOTYPE values (待测试).

@export var follow_time: float = 0.5
@export var follow_per_mark: float = 0.1
## Horizontal speed limit of the following circle (m/s).
@export var follow_speed: float = 12.0
## Locked (no longer moving) part of the telegraph: the dodge window.
@export var lock_time: float = 0.6
@export var radius: float = 5.0
## Each mark stack on the target shrinks the circle (more precise, same delay).
@export var radius_per_mark: float = -0.8
@export var min_radius: float = 2.6
@export var beam_duration: float = 0.35
@export var sky_height: float = 45.0
@export var max_call_range: float = 60.0
## Fallback point ahead of the caster when nothing is locked (m).
@export var unlocked_distance: float = 24.0

@export_group("Burn (playtest round 2: heavy strike)")
## Ground fire left in the circle after the beam (null = none). Each tick
## is a separate EXPLOSION hit through DamageSystem (guardable, no stagger).
@export var burn_attack: AttackDefinition
@export var burn_duration: float = 3.0
@export var burn_interval: float = 0.5

@export_group("Shockwave (playtest round 5: fast heavy strike)")
## Ring blast around the beam: mechs outside the circle but within
## `shock_radius` take this EXPLOSION (guardable, pushed outward).
@export var shock_attack: AttackDefinition
@export var shock_radius: float = 11.0
