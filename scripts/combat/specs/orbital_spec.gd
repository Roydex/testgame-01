class_name OrbitalSpec
extends Resource
## Delayed orbital strike (AZURE ORACLE 轨道激光). A ground circle shows for
## `telegraph` seconds at the target's position at call time (it does not
## follow), then a vertical BEAM hits everything inside whose line to the sky
## is clear: roofs block it. PROTOTYPE values (待测试).

@export var telegraph: float = 1.2
@export var radius: float = 5.0
## Each mark stack on the target shrinks the circle (more precise, same delay).
@export var radius_per_mark: float = -0.8
@export var min_radius: float = 2.6
@export var beam_duration: float = 0.35
@export var sky_height: float = 45.0
@export var max_call_range: float = 60.0
## Fallback point ahead of the caster when nothing is locked (m).
@export var unlocked_distance: float = 24.0
