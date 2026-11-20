class_name UltimateEffect
extends Resource
## Behaviour of one mech's signature ultimate (phase 3b). UltimateSystem
## runs the shared phases (LOCKED → READY → WINDUP → active → cost) and calls
## these hooks; the effect only touches the mech through its kit, statuses,
## MovementModifier and DamageSystem, like every other combat code.
## Stateless: per-mech runtime state lives in `us.fx` (two mechs can share
## the same .tres). PALE SERAPH's judgment predates this (effect = null).

## Active phase starts / ticks (not during hitstop) / ends.
func begin(_us: UltimateSystem) -> void:
	pass


func tick(_us: UltimateSystem, _delta: float) -> void:
	pass


func end(_us: UltimateSystem) -> void:
	pass


## Cost phase starts / ends (the generic overload modifier is already applied).
func begin_cost(_us: UltimateSystem) -> void:
	pass


func end_cost(_us: UltimateSystem) -> void:
	pass


## Extra HUD text while active (after the remaining time).
func hud_active(_us: UltimateSystem) -> String:
	return ""
