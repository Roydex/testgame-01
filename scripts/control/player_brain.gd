class_name PlayerBrain
extends Node
## Converts keyboard / mouse input into a MechCommand. Movement is relative
## to the camera's horizontal yaw; vertical thrust is independent. When a
## target is locked the mech faces it (strafing), otherwise it faces travel.

var motor: MechMotor
var camera_rig: CameraRig
var targeting: TargetingSystem
var enabled: bool = true
var _reticle: PlacementReticle


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
	cmd.descend_pressed = cmd.descend_pressed or Input.is_action_just_pressed(&"descend")
	# OR-in edges so a press is never lost between motor ticks
	cmd.jump_pressed = cmd.jump_pressed or Input.is_action_just_pressed(&"jump_ascend")
	cmd.dash_pressed = cmd.dash_pressed or Input.is_action_just_pressed(&"dash")
	var combat0 := motor.get_node_or_null(^"CombatStateMachine") as CombatStateMachine
	if combat0 and combat0.aim_pending():
		var to0 := combat0.placement_point - motor.global_position
		cmd.face_dir = Vector3(to0.x, 0.0, to0.z)
	elif targeting.has_target():
		var to := targeting.get_target_point() - motor.global_position
		cmd.face_dir = Vector3(to.x, 0.0, to.z)
	elif Experiments.free_aim:
		cmd.face_dir = camera_rig.get_yaw_basis() * Vector3.FORWARD  # shooter stance: face the crosshair
	else:
		cmd.face_dir = Vector3.ZERO
	# combat intent (mouse buttons only count while the mouse is captured,
	# so the click that captures it never fires an attack)
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	cmd.attack_pressed = cmd.attack_pressed or (captured and Input.is_action_just_pressed(&"attack"))
	cmd.guard_held = captured and Input.is_action_pressed(&"guard")
	cmd.attack_held = captured and Input.is_action_pressed(&"attack")
	cmd.skill_held = Input.is_action_pressed(&"skill")
	cmd.parry_pressed = cmd.parry_pressed or Input.is_action_just_pressed(&"parry")
	cmd.skill_pressed = cmd.skill_pressed or Input.is_action_just_pressed(&"skill")
	cmd.ult_pressed = cmd.ult_pressed or Input.is_action_just_pressed(&"ultimate")
	var combat := motor.get_node_or_null(^"CombatStateMachine") as CombatStateMachine
	if combat:
		combat.aim_target = targeting.current if targeting.has_target() else null
		combat.free_aim_active = Experiments.free_aim
		_update_view_point(combat)
		if Experiments.free_aim:
			_update_free_aim(combat)
			if combat.aim_target == null:
				combat.aim_target = combat.free_aim_target  # melee lunges steer to what you aim at
		update_placement_aim(combat)


## Hand-marked ground strike (AIM state): raise the camera, cast the view
## ray onto the ground (clamped to the call range) and show the ghost.
## Public so the scripted demo can drive it while the brain is disabled.
func update_placement_aim(combat: CombatStateMachine) -> void:
	var aiming := combat.aim_pending()
	camera_rig.set_placement_mode(aiming)
	if not aiming:
		if _reticle:
			_reticle.visible = false
		return
	if _reticle == null:
		_reticle = PlacementReticle.new()
		camera_rig.add_child(_reticle)
	var cam := camera_rig.camera
	var origin := cam.global_position
	var fwd := -cam.global_basis.z
	var def := combat.aim_def
	var spec := def.orbital_spec if def and def.orbital_spec else OrbitalSpec.new()
	var q := PhysicsRayQueryParameters3D.create(origin, origin + fwd * 400.0, CombatTypes.WORLD_LAYER)
	q.exclude = [motor.get_rid()]
	var hit := motor.get_world_3d().direct_space_state.intersect_ray(q)
	var p: Vector3 = hit.position if not hit.is_empty() else origin + fwd * spec.max_call_range
	p = OrbitalStrike.clamp_to_range(motor.global_position, p, spec.max_call_range)
	p = OrbitalStrike.ground_point(motor.get_world_3d(), p + Vector3.UP * 2.0)
	combat.placement_point = p
	combat.placement_set = true
	var on_target := false
	for t in TeamRules.get_valid_targets(motor, &"mechs"):
		if Vector2(t.global_position.x - p.x, t.global_position.z - p.z).length() <= spec.radius:
			on_target = true
			break
	_reticle.show_at(p, spec.radius, on_target)

## Screen-centre point (mirror shield reflected light without a lock):
## camera ray starting at the mech's depth, first wall hit or far away.
func _update_view_point(combat: CombatStateMachine) -> void:
	var cam := camera_rig.camera
	if cam == null:
		combat.view_point_valid = false
		return
	var origin := cam.global_position
	var fwd := -cam.global_basis.z
	var start := origin + fwd * maxf((motor.global_position - origin).dot(fwd), 0.0)
	var q := PhysicsRayQueryParameters3D.create(start, origin + fwd * 120.0, CombatTypes.WORLD_LAYER)
	q.exclude = [motor.get_rid()]
	var hit := motor.get_world_3d().direct_space_state.intersect_ray(q)
	combat.view_point = hit.position if not hit.is_empty() else origin + fwd * 120.0
	combat.view_point_valid = true


## 自由瞄准: crosshair ray from the camera (starting at the mech's depth so
## nothing between camera and mech is aimed at) plus a small aim assist.
func _update_free_aim(combat: CombatStateMachine) -> void:
	var cam := camera_rig.camera
	var origin := cam.global_position
	var fwd := -cam.global_basis.z
	var best: Node3D = null
	var best_a := deg_to_rad(Experiments.AIM_ASSIST_DEG)
	for t in TeamRules.get_valid_targets(motor):
		var p: Vector3 = t.call(&"get_lock_point") if t.has_method(&"get_lock_point") else t.global_position + Vector3.UP * 2.0
		var to := p - origin
		if to.length() > Experiments.AIM_MAX_DISTANCE or to.dot(fwd) <= 0.0:
			continue
		var a := fwd.angle_to(to)
		if a < best_a and CombatTypes.has_line_of_sight(motor.get_world_3d(), motor.global_position + Vector3.UP * 2.6, p):
			best_a = a
			best = t
	combat.free_aim_target = best
	var start := origin + fwd * maxf((motor.global_position - origin).dot(fwd), 0.0)
	var q := PhysicsRayQueryParameters3D.create(start, origin + fwd * Experiments.AIM_MAX_DISTANCE, CombatTypes.WORLD_LAYER)
	q.exclude = [motor.get_rid()]
	var hit := motor.get_world_3d().direct_space_state.intersect_ray(q)
	combat.free_aim_point = hit.position if not hit.is_empty() else origin + fwd * Experiments.AIM_MAX_DISTANCE
