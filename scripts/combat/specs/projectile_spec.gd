class_name ProjectileSpec
extends Resource
## Extra projectile behaviour for AttackDefinition.delivery == PROJECTILE:
## multi-pellet spread, distance falloff, limited homing, shoot-down
## durability, impact splash and charge scaling. PROTOTYPE values (待测试).
## Speed / range / radius stay on AttackDefinition.

@export var pellets: int = 1
## Full cone angle of the pellet fan (deg).
@export var spread_deg: float = 0.0

@export_group("Falloff")
## Full damage up to falloff_start, linear down to falloff_min_mult at falloff_end (m).
@export var falloff_start: float = 0.0
@export var falloff_end: float = 0.0
@export var falloff_min_mult: float = 1.0
## Range multiplier when aiming steeply up (> 30°): high-angle fire reaches less far.
@export var steep_range_mult: float = 1.0

@export_group("Homing")
## Max turn rate toward the target (deg/s). 0 = straight. Never instant.
@export var homing_deg: float = 0.0
## No homing (and no splash) before travelling this far: point-blank shots don't track.
@export var arming_distance: float = 0.0

@export_group("Shoot-down")
## > 0: the projectile has a hurtbox and this much HP, so it can be shot down.
@export var shootable_hp: float = 0.0

@export_group("Impact splash")
## > 0: an EXPLOSION of this radius on impact (cover-checked, guardable, not parryable).
@export var splash_radius: float = 0.0
@export var splash_attack: AttackDefinition

@export_group("Charge scaling (charge attacks)")
## Damage multiplier at full charge (linear from 1 at minimum charge).
@export var charge_damage_mult: float = 1.0
@export var charge_speed_mult: float = 1.0
## At this charge level or above the shot breaks guards.
@export var charge_guard_break_at: float = 2.0

@export_group("Presentation")
@export var color: Color = Color(1.0, 0.45, 0.15)
