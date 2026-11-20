class_name DeployConfig
extends KitConfig
## VERDANT ARK deployables. PROTOTYPE values (待测试).

@export var max_turrets: int = 2
## Fortress: damage taken multiplier while within this range of an own turret.
@export var fortress_radius: float = 12.0
@export var fortress_damage_taken: float = 0.85
@export_group("Shield wall (盾墙, playtest round 2)")
## Pressing guard raises an energy wall ahead (one at a time). It blocks
## hostile shots and melee, allies shoot through it, it has its own HP and
## lifetime; the cooldown starts when it is gone.
@export var wall_enabled: bool = true
@export var wall_hp: float = 150.0
@export var wall_lifetime: float = 8.0
@export var wall_cooldown: float = 4.5
@export var wall_size: Vector3 = Vector3(6.0, 4.5, 0.6)
@export var wall_distance: float = 3.5
@export_group("Symbiotic shell (共生龟甲, round 6)")
## Each blocked hit alerts the own turrets: they turn on the attacker and
## fire faster for a while (range and line of sight still apply).
@export var alert_time: float = 2.0
@export var alert_rate_mult: float = 1.5
@export_group("Spore burst parry (孢囊爆散, round 6)")
## A successful F parry bursts spores around the ark: hostile mechs nearby
## are pushed and snared (status). Internal cooldown between bursts.
@export var spore_radius: float = 5.0
@export var spore_push: float = 8.0
@export var spore_status: StatusEffectDefinition
@export var spore_cooldown: float = 3.0


func create_kit() -> MechKit:
	return DeployKit.new()
