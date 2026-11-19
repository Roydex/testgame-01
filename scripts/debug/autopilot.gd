extends Node
## Scripted showcase run in the real (windowed, rendered) game. Drives the
## player motor through the same MechCommand path a brain uses, saves
## screenshots and prints a motion-state trace. Used for visual verification.

var scene: Node3D
var motor: MechMotor
var out_dir: String
var trace: PackedStringArray = []
var _frame_times: PackedFloat32Array = []
var _measuring := false


func run(p_scene: Node3D) -> void:
	scene = p_scene
	motor = scene.motor
	scene.brain.enabled = false
	scene.rig.mouse_enabled = false
	motor.record_transitions = true
	out_dir = ProjectSettings.globalize_path("res://docs/screenshots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	motor.motion_state_changed.connect(func(_o: int, n: int):
		trace.append("%.2f %s" % [Time.get_ticks_msec() / 1000.0, MechMotor.STATE_NAMES[n]]))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_sequence.call_deferred()


func _process(delta: float) -> void:
	if _measuring:
		_frame_times.append(delta)


func _fps_report() -> void:
	if _frame_times.is_empty():
		return
	var total := 0.0
	var worst := 0.0
	var sorted := _frame_times.duplicate()
	sorted.sort()
	for d in _frame_times:
		total += d
		worst = maxf(worst, d)
	var p99 := sorted[int(sorted.size() * 0.99)]
	print("[autopilot] perf: %d frames, viewport %s, avg %.1f FPS, 1%%-low %.1f FPS, worst frame %.1f ms (vsync off, %s)" % [
		_frame_times.size(), get_viewport().get_visible_rect().size, _frame_times.size() / total, 1.0 / p99, worst * 1000.0,
		RenderingServer.get_video_adapter_name()])


func _hold(seconds: float, move := Vector3.ZERO, ascend := false, descend := false) -> void:
	var t := 0.0
	while t < seconds:
		motor.command.move = move
		motor.command.ascend = ascend
		motor.command.descend = descend
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _press_jump() -> void:
	motor.command.jump_pressed = true


func _press_dash() -> void:
	motor.command.dash_pressed = true


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("[autopilot] screenshot %s  state=%s pos=%s en=%.1f" % [path, motor.get_state_name(), motor.global_position, motor.en])


func _sequence() -> void:
	await _hold(1.0)
	await _shot("01_spawn_grounded")
	_measuring = true
	var fwd := Vector3(0, 0, -1)
	await _hold(0.6, fwd)
	_press_dash()
	await _hold(0.15, fwd)
	await _shot("02_ground_dash_fov")
	await _hold(0.25, fwd)
	_press_jump()
	await _hold(0.1, fwd, true)
	await _hold(1.2, fwd, true)
	await _shot("03_ascend")
	await _hold(0.6, fwd)
	await _shot("04_hover")
	_press_dash()
	await _hold(0.12, Vector3(1, 0, -1).normalized())
	await _shot("05_air_dash")
	await _hold(0.4, Vector3(1, 0, -1).normalized())
	await _hold(2.5, Vector3.ZERO, false, true)
	await _shot("06_descend_landed")
	# lock-on: bobbing target T3
	scene.targeting.toggle_lock()
	var t3 := scene.get_node("Graybox/T3_bobbing") as Node3D
	scene.targeting._set_target(t3, "autopilot")
	await _hold(1.2)
	await _shot("07_lock_bobbing_target")
	await _hold(1.8)
	await _shot("08_lock_bobbing_target_later")
	# fly up while locked
	_press_jump()
	await _hold(1.5, Vector3(1, 0, 0), true)
	await _shot("09_lock_airborne_strafe")
	await _hold(2.5, Vector3.ZERO, false, true)
	# camera occlusion: walk behind the thick wall facing it
	scene.targeting.toggle_lock()
	motor.reset_to(Vector3(0, 0.2, -44))
	scene.rig.yaw = 0.0
	scene.rig.snap()
	await _hold(1.0, Vector3(0, 0, 1))
	await _hold(0.8)
	await _shot("10_occlusion_wall_close")
	# under the low slab, then up through the open side
	motor.reset_to(GrayboxBuilder.POINTS.slab_under)
	scene.rig.snap()
	await _hold(0.8)
	_press_jump()
	await _hold(2.0, Vector3.ZERO, true)
	await _shot("11_under_slab_ceiling")
	await _hold(2.5, Vector3.ZERO, false, true)
	_measuring = false
	_fps_report()
	print("[autopilot] trace: ", " | ".join(trace))
	print("[autopilot] done")
	get_tree().quit(0)
