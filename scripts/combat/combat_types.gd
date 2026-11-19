class_name CombatTypes
extends RefCounted
## Shared combat enums.

enum AttackType { MELEE, PROJECTILE, BEAM, EXPLOSION, GRAB }
enum HitResult { IGNORED, HIT, GUARDED, GUARD_BREAK, PARRIED, REFLECTED, DEFLECTED, EVADED }
## How an attack delivers its hit. Timing (windup / active / recovery /
## cooldown) is the same for every delivery.
enum Delivery { HITBOX, PROJECTILE, GRAPPLE, ORBITAL, DEPLOY, SELF }

const RESULT_NAMES := ["IGNORED", "HIT", "GUARDED", "GUARD_BREAK", "PARRIED", "REFLECTED", "DEFLECTED", "EVADED"]
const TYPE_NAMES := ["MELEE", "PROJECTILE", "BEAM", "EXPLOSION", "GRAB"]

## Physics layer used by Hurtbox areas (layer 5).
const HURTBOX_LAYER := 16
## World geometry (cover, line-of-sight).
const WORLD_LAYER := 1


static func is_parryable_type(t: int) -> bool:
	## Mirror shield rule: melee and projectiles can be parried; beams,
	## explosions and grabs cannot.
	return t == AttackType.MELEE or t == AttackType.PROJECTILE


static func is_guardable_type(t: int) -> bool:
	## Grabs can only be dodged.
	return t != AttackType.GRAB


## True when nothing on the world layer lies between a and b (cover check).
static func has_line_of_sight(world: World3D, a: Vector3, b: Vector3, exclude: Array[RID] = []) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, WORLD_LAYER)
	q.exclude = exclude
	return world.direct_space_state.intersect_ray(q).is_empty()
