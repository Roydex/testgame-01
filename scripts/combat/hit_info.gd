class_name HitInfo
extends RefCounted
## One hit request, resolved by DamageSystem. Detection (Hitbox / Projectile)
## creates it; DamageSystem decides the outcome; CombatFeedback presents it.

var attacker: Node3D       ## mech responsible (projectile owner for shots)
var victim: Node3D         ## mech hit
var attack: AttackDefinition
var projectile: Node3D     ## set for projectile hits
## Where the hit comes from (attacker or projectile position) — used for
## the frontal guard / parry arc.
var source_position: Vector3
var hit_position: Vector3
var direction: Vector3
var damage_mult: float = 1.0
## Clean-hit knockback multiplier (速度即伤害 experiment).
var knockback_mult: float = 1.0
## Closing-speed bonus applied to this hit (1 = none), for presentation.
var momentum_mult: float = 1.0
## Unguardable / unparryable override (counters, off-balance punishes).
var force_unblockable: bool = false
## Guard break override (fully charged railgun shot).
var force_guard_break: bool = false
## Non-mech source that dealt the hit (turret, grapple, orbital strike, blast).
var source_entity: Node3D
var result: int = CombatTypes.HitResult.IGNORED
var final_damage: float = 0.0
