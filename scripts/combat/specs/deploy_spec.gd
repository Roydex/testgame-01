class_name DeploySpec
extends Resource
## Deployables (VERDANT ARK): an autonomous turret or a restraint zone.
## PROTOTYPE values (待测试).

enum Kind { TURRET, ZONE }

@export var kind: Kind = Kind.TURRET
## Placement: in front of the owner (turret) or at the lock target (zone),
## projected to the ground; cover between owner and the point shortens it.
@export var place_distance: float = 3.5
@export var max_place_range: float = 22.0
@export var lifetime: float = 20.0

@export_group("Turret")
@export var hp: float = 70.0
## Turret grows for this long before it can fire (readable spawn).
@export var arm_time: float = 0.7
@export var fire_range: float = 28.0
@export var fire_interval: float = 0.9
## Limited turn rate: fast air dashers can outrun its aim.
@export var turn_rate_deg: float = 110.0
@export var shot: AttackDefinition

@export_group("Zone")
@export var radius: float = 7.0
@export var zone_status: StatusEffectDefinition
