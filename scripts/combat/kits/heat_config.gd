class_name HeatConfig
extends KitConfig
## HELLFANG furnace heat. PROTOTYPE values (待测试).

@export var max_heat: float = 100.0
## Passive cooling (per s) after `decay_delay` s without gaining heat.
@export var decay_per_sec: float = 14.0
@export var decay_delay: float = 1.0
## Cooling multiplier while guarding (guard keeps the furnace warm).
@export var guard_decay_mult: float = 0.35
@export var heat_per_dash: float = 10.0
## Heat gained per point of damage blocked.
@export var guard_heat_per_damage: float = 0.5
@export_group("Scorching tier (high heat bonus)")
@export var scorch_threshold: float = 70.0
@export var scorch_damage_mult: float = 1.3
@export_group("Overheat (penalty)")
@export var overheat_duration: float = 1.6
## Whiffing a move that overheats on a miss (overdrive ram) vents longer.
@export var whiff_overheat_duration: float = 2.2
@export var overheat_damage_taken: float = 1.3
@export var overheat_speed_mult: float = 0.75
## Heat left after an overheat.
@export var overheat_reset: float = 40.0


func create_kit() -> MechKit:
	return HeatKit.new()
