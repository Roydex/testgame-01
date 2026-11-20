class_name GrappleSpec
extends Resource
## Magnetic grapple (HELLFANG 磁索钩爪). Flies with travel time (dodgeable),
## stops on cover. On a GRAB hit: a grounded target pulls the owner in; an
## airborne target is dragged down. PROTOTYPE values (待测试).

@export var speed: float = 62.0
@export var max_range: float = 25.0
@export var radius: float = 0.5
## A target this high above the ground counts as airborne (m).
@export var airborne_height: float = 2.5
@export_group("Pull self (grounded target)")
@export var pull_self_speed: float = 30.0
## Stop this far from the target.
@export var pull_stop_distance: float = 3.2
@export var pull_max_time: float = 0.9
@export_group("Drag target down (airborne target)")
@export var drag_down_speed: float = 14.0
@export var drag_down_time: float = 0.45
## Hard-control (stagger) on the grabbed target; goes through CC protection.
## The grab always interrupts the target first (charge, windup, deploy,
## guard), whatever CC protection leaves of the stagger. The stagger then
## lasts the expected pull / drag time + `grab_stagger_tail`, clamped to
## [grab_stagger, grab_stagger_max], so the target is still staggered when
## HELLFANG arrives (playtest feedback 2026-11-19).
@export var grab_stagger: float = 0.45
@export var grab_stagger_tail: float = 0.3
@export var grab_stagger_max: float = 1.0
@export_group("Miss")
## Extra recovery when the hook misses (retracting the cable).
@export var miss_recovery: float = 0.55
## Playtest round 5: a miss (or a wall latch) only puts the hook on this
## cooldown; a grab keeps the attack's full cooldown, so the hit rate a
## HELLFANG can sustain is unchanged.
@export var miss_cooldown: float = 1.8
## How fast the claw reels back to the arm after a miss (visual, m/s).
@export var retract_speed: float = 90.0
@export_group("Wall latch (钩墙位移)")
## Hitting a wall / pillar side (not floor or ceiling) latches the claw and
## pulls the owner to it: a mobility move, no damage, no stagger.
@export var wall_latch: bool = true
## |normal.y| below this counts as a wall.
@export var wall_max_normal_y: float = 0.55
@export var wall_pull_speed: float = 30.0
@export var wall_stop_distance: float = 2.2
@export var wall_max_time: float = 0.9
