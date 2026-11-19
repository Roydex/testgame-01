class_name CombatTypes
extends RefCounted
## Shared combat enums.

enum AttackType { MELEE, PROJECTILE, BEAM, EXPLOSION, GRAB }
enum HitResult { IGNORED, HIT, GUARDED, GUARD_BREAK, PARRIED, REFLECTED, DEFLECTED }

const RESULT_NAMES := ["IGNORED", "HIT", "GUARDED", "GUARD_BREAK", "PARRIED", "REFLECTED", "DEFLECTED"]

## Physics layer used by Hurtbox areas (layer 5).
const HURTBOX_LAYER := 16


static func is_parryable_type(t: int) -> bool:
	## Mirror shield rule: melee and projectiles can be parried; beams,
	## explosions and grabs cannot.
	return t == AttackType.MELEE or t == AttackType.PROJECTILE


static func is_guardable_type(t: int) -> bool:
	return t != AttackType.GRAB
