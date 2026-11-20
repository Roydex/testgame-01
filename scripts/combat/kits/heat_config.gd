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
@export_group("Furnace guard (熔炉格挡, playtest round 2)")
## Released after a guard that absorbed at least `furnace_min_absorbed`
## damage: a radial blast whose damage = base + absorbed × per (absorbed capped).
@export var furnace_burst: AttackDefinition
@export var furnace_min_absorbed: float = 6.0
@export var furnace_damage_per_absorbed: float = 1.0
@export var furnace_absorb_cap: float = 40.0
@export_group("Scorching tier (high heat bonus)")
@export var scorch_threshold: float = 70.0
@export var scorch_damage_mult: float = 1.3
@export_group("Overheat (penalty)")
## Playtest round 5: lighter (1.6 → 1.0 s, ram whiff 2.2 → 1.5 s, damage
## taken ×1.3 → ×1.15, speed ×0.75 → ×0.85), dashing allowed, and the
## furnace vents a steam ring that pushes enemies away.
@export var overheat_duration: float = 1.0
## Whiffing a move that overheats on a miss (overdrive ram) vents longer.
@export var whiff_overheat_duration: float = 1.5
@export var overheat_damage_taken: float = 1.15
@export var overheat_speed_mult: float = 0.85
@export var overheat_blocks_dash: bool = false
@export var steam_radius: float = 5.0
@export var steam_push: float = 12.0
## Heat left after an overheat.
@export var overheat_reset: float = 40.0


func create_kit() -> MechKit:
	return HeatKit.new()

@export_group("Bite (步进咬合, playtest round 5)")
## A landed axe swing bites the victim: this status on it (readable), and
## for its duration HELLFANG's swings lunge farther and steer harder at it
## and its dashes swerve onto it.
@export var bite_status: StatusEffectDefinition
@export var bite_lunge_mult: float = 2.2
@export var bite_steer_bonus_deg: float = 150.0
@export var bite_dash_home_range: float = 18.0
@export var bite_dash_home_angle_deg: float = 100.0
