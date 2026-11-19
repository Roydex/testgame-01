class_name KitConfig
extends Resource
## Base data for a mech's resource system. Subclasses create their kit.

func create_kit() -> MechKit:
	return MechKit.new()
