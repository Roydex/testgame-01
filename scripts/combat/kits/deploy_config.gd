class_name DeployConfig
extends KitConfig
## VERDANT ARK deployables. PROTOTYPE values (待测试).

@export var max_turrets: int = 2
## Fortress: damage taken multiplier while within this range of an own turret.
@export var fortress_radius: float = 12.0
@export var fortress_damage_taken: float = 0.85


func create_kit() -> MechKit:
	return DeployKit.new()
