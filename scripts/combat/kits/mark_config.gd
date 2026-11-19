class_name MarkConfig
extends KitConfig
## AZURE ORACLE marks (the mark status itself lives on the pulse shot's
## status_effects). PROTOTYPE values (待测试).

@export var mark_id: StringName = &"mark"


func create_kit() -> MechKit:
	return MarkKit.new()
