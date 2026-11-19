class_name MovementModifier
extends RefCounted
## A restriction / correction that skills, combat states or hit reactions
## push onto MechMotor. Combat code never writes motor velocity directly:
## it adds a modifier (and optionally an impulse via MechMotor.apply_impulse).

var id: StringName
## Seconds remaining; < 0 means until removed explicitly.
var duration: float = -1.0
var speed_mult: float = 1.0
var accel_mult: float = 1.0
var turn_mult: float = 1.0
## Clamped to [0.5, 3.0] by the motor so no modifier can create zero gravity.
var gravity_mult: float = 1.0
var block_move: bool = false
var block_jump: bool = false
var block_dash: bool = false
## Blocks ascend AND hover (the mech will fall).
var block_thrust: bool = false
var block_facing: bool = false


static func create(p_id: StringName, p_duration: float = -1.0) -> MovementModifier:
	var m := MovementModifier.new()
	m.id = p_id
	m.duration = p_duration
	return m


func describe() -> String:
	var flags: PackedStringArray = []
	if block_move: flags.append("noMove")
	if block_jump: flags.append("noJump")
	if block_dash: flags.append("noDash")
	if block_thrust: flags.append("noThrust")
	if block_facing: flags.append("noFace")
	if not is_equal_approx(speed_mult, 1.0): flags.append("spd×%.2f" % speed_mult)
	return "%s[%s]%s" % [id, ",".join(flags), (" %.1fs" % duration) if duration >= 0.0 else ""]
