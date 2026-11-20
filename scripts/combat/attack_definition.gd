class_name AttackDefinition
extends Resource
## Data for one attack (melee swing, lunge, projectile shot). Timing in
## seconds, distances in metres. PROTOTYPE values (待测试).

@export var id: StringName = &"attack"
@export var display_name: String = "Attack"
@export var attack_type: CombatTypes.AttackType = CombatTypes.AttackType.MELEE
## How the hit is delivered (hitbox sweep, projectile, grapple, orbital
## strike, deployable, or a self action such as a vent / backstep).
@export var delivery: CombatTypes.Delivery = CombatTypes.Delivery.HITBOX

@export_group("Timing")
@export var windup: float = 0.15
@export var active: float = 0.1
@export var recovery: float = 0.3
## Time from attack start after which recovery can be cancelled by
## dash / guard / parry / jump (the "cancel window").
@export var cancel_time: float = 0.35
## Attack chained when the attack button is buffered (combo). Empty = end.
@export var next_attack: AttackDefinition
## Input buffer: presses this long before the chain point still count.
@export var buffer_time: float = 0.25
## Major attacks broadcast a telegraph at windup start (counter window).
@export var telegraphed: bool = false

## Extra recovery when the attack hits nothing (a whiffed heavy swing).
@export var whiff_recovery_extra: float = 0.0

@export_group("Damage")
@export var damage: float = 8.0
@export var guardable: bool = true
@export var guard_break: bool = false
@export var parryable: bool = true
@export var knockback: float = 4.0
@export var knockback_up: float = 1.0
## Stagger applied on a clean hit (s). 0 = flinch only (hitstop).
@export var stagger_time: float = 0.25
@export var hitstop: float = 0.06
## Camera shake strength on hit (0..1), capped by CombatFeedback.
@export var shake: float = 0.15

## Statuses applied to the victim on a clean hit (and on a guarded hit
## when status_on_guard is set).
@export var status_effects: Array[StatusEffectDefinition] = []
@export var status_on_guard: bool = false

@export_group("Hitbox (local space, -Z forward)")
@export var hitbox_offset: Vector3 = Vector3(0, 2.4, -2.2)
@export var hitbox_size: Vector3 = Vector3(2.2, 2.4, 3.0)

@export_group("Movement during the attack")
@export_range(0.0, 1.0) var windup_speed_mult: float = 0.35
@export_range(0.0, 1.0) var active_speed_mult: float = 0.2
@export_range(0.0, 1.0) var recovery_speed_mult: float = 0.45
@export var turn_mult: float = 0.4
## Forward lunge during the active phase (m/s, 0 = none).
@export var lunge_speed: float = 0.0
## Lunge starts at windup end and lasts this long (can exceed `active`:
## the hitbox stays live while lunging).
@export var lunge_duration: float = 0.0
## Horizontal steering toward the lock target while lunging (deg/s).
@export var lunge_steer_deg: float = 0.0
## Vertical tracking toward the lock target: max vertical speed (m/s) and
## max height difference that is tracked at all (m). 0 = none.
@export var vertical_track_speed: float = 0.0
@export var vertical_track_range: float = 0.0
## Stop the lunge when hitting a wall.
@export var stop_on_wall: bool = true

@export_group("Cost")
@export var en_cost: float = 0.0
@export var cooldown: float = 0.0

@export_group("Projectile")
@export var projectile_speed: float = 45.0
@export var projectile_range: float = 120.0
@export var projectile_radius: float = 0.35

@export_group("Delivery specs")
@export var projectile_spec: ProjectileSpec
@export var grapple_spec: GrappleSpec
@export var orbital_spec: OrbitalSpec
@export var deploy_spec: DeploySpec
## Hold skill aimed by hand first (AIM state, the brain marks a ground
## point; release fires). AZURE orbital, playtest round 3.
@export var aim_placement: bool = false

@export_group("Self action")
## Invulnerable for this long from the start of the active phase (backstep).
@export var invuln_time: float = 0.0
## Non-damaging push on hostile mechs within this radius at active start.
@export var repulse_radius: float = 0.0
@export var repulse_force: float = 0.0
## Radial EXPLOSION around the attacker at active start (HELLFANG 爆燃反震).
@export var self_blast_radius: float = 0.0

@export_group("Mech resource (read by the mech's kit)")
## HELLFANG heat: added when the attack starts / when it lands.
@export var heat_cost: float = 0.0
@export var heat_on_hit: float = 0.0
## Attack needs at least this much heat (overdrive ram).
@export var min_heat: float = 0.0
## Heat removed per second during the active phase (active vent).
@export var heat_vent_rate: float = 0.0
## A whiff forces an overheat (overdrive ram).
@export var whiff_overheats: bool = false
## AZURE ORACLE marks: damage bonus per mark stack on the victim, consumed on hit.
@export var mark_consume_bonus: float = 0.0


## Delivery, with the 2b data convention kept: a PROJECTILE-type attack
## without an explicit delivery fires a projectile.
func get_delivery() -> int:
	if delivery == CombatTypes.Delivery.HITBOX and attack_type == CombatTypes.AttackType.PROJECTILE:
		return CombatTypes.Delivery.PROJECTILE
	return delivery


func total_time() -> float:
	return windup + maxf(active, lunge_duration) + recovery
