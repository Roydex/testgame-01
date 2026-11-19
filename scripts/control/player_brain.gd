class_name PlayerBrain
extends Node
## Converts keyboard / mouse input into a MechCommand. Movement is relative
## to the camera's horizontal yaw; vertical thrust is independent. When a
## target is locked the mech faces it (strafing), otherwise it faces travel.

var motor: MechMotor
var camera_rig: CameraRig
var targeting: TargetingSystem
var enabled: bool = true


func setup(p_motor: MechMotor, p_rig: CameraRig, p_targeting: TargetingSystem) -> void:
	motor = p_motor
	camera_rig = p_rig
	targeting = p_targeting
	process_physics_priority = -10  # run before the motor


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or targeting == null:
		return
	if event.is_action_pressed(&"lock_toggle"):
		targeting.toggle_lock()
	elif event.is_action_pressed(&"target_next"):
		targeting.cycle(1)
	elif event.is_action_pressed(&"target_prev"):
		targeting.cycle(-1)


func _physics_process(_delta: float) -> void:
	if not enabled or motor == null:
		return
	var cmd := motor.command
	var iv := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	cmd.move = camera_rig.get_yaw_basis() * Vector3(iv.x, 0.0, iv.y)
	cmd.ascend = Input.is_action_pressed(&"jump_ascend")
	cmd.descend = Input.is_action_pressed(&"descend")
	# OR-in edges so a press is never lost between motor ticks
	cmd.jump_pressed = cmd.jump_pressed or Input.is_action_just_pressed(&"jump_ascend")
	cmd.dash_pressed = cmd.dash_pressed or Input.is_action_just_pressed(&"dash")
	if targeting.has_target():
		var to := targeting.get_target_point() - motor.global_position
		cmd.face_dir = Vector3(to.x, 0.0, to.z)
	else:
		cmd.face_dir = Vector3.ZERO
	# combat intent (mouse buttons only count while the mouse is captured,
	# so the click that captures it never fires an attack)
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	cmd.attack_pressed = cmd.attack_pressed or (captured and Input.is_action_just_pressed(&"attack"))
	cmd.guard_held = captured and Input.is_action_pressed(&"guard")
	cmd.parry_pressed = cmd.parry_pressed or Input.is_action_just_pressed(&"parry")
	cmd.skill_pressed = cmd.skill_pressed or Input.is_action_just_pressed(&"skill")
	cmd.ult_pressed = cmd.ult_pressed or Input.is_action_just_pressed(&"ultimate")
	var combat := motor.get_node_or_null(^"CombatStateMachine") as CombatStateMachine
	if combat:
		combat.aim_target = targeting.current if targeting.has_target() else null
