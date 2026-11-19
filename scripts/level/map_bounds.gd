class_name MapBounds
extends Node3D
## Absolute flight limits for a map. MechMotor reads the first node in the
## "map_bounds" group. Horizontal limits are also backed by physical walls
## built by the level; this node is the authoritative ceiling.

@export var ceiling_y: float = 40.0
@export var kill_y: float = -30.0
@export var half_extent: Vector2 = Vector2(100.0, 100.0)


func _enter_tree() -> void:
	add_to_group(&"map_bounds")


func clamp_horizontal(p: Vector3) -> Vector3:
	var c := global_position
	p.x = clampf(p.x, c.x - half_extent.x, c.x + half_extent.x)
	p.z = clampf(p.z, c.z - half_extent.y, c.z + half_extent.y)
	return p
