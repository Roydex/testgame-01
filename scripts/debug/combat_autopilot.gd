extends Node
## Scripted COMBAT showcase in the real rendered game (`-- --combat-demo`).
## Drives the player through MechCommand only; saves screenshots to
## docs/screenshots/combat_*.png and prints the combat event log.

var scene: Node3D
var motor: MechMotor
var combat: CombatStateMachine
var melee: MechMotor
var ranged: MechMotor
var out_dir: String
var log: PackedStringArray = []
var _frame_times: PackedFloat32Array = []
var _skip := 0


func _process(delta: float) -> void:
	if _skip > 0:
		_skip -= 1  # ignore the readback stall around screenshots
	elif scene != null:
		_frame_times.append(delta)


func run(p_scene: Node3D) -> void:
	scene = p_scene
	motor = scene.motor
	combat = scene.combat
	scene.brain.enabled = false
	scene.rig.mouse_enabled = false
	melee = scene.dummies[0]
	ranged = scene.dummies[1]
	out_dir = ProjectSettings.globalize_path("res://docs/screenshots")
	CombatEvents.hit_resolved.connect(func(h: HitInfo): log.append("%.2f %s→%s %s %s %.1f" % [
		Time.get_ticks_msec() / 1000.0, h.attacker.name, h.victim.name, h.attack.display_name, CombatTypes.RESULT_NAMES[h.result], h.final_damage]))
	CombatEvents.ultimate_phase.connect(func(m: Node3D, p: String): log.append("%.2f %s ULT %s" % [Time.get_ticks_msec() / 1000.0, m.name, p]))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_sequence.call_deferred()


func _brain(d: MechMotor) -> SparringBrain:
	return d.get_node(^"SparringBrain") as SparringBrain


func _hold(seconds: float, each := Callable()) -> void:
	var t := 0.0
	while t < seconds:
		_face_lock()
		if each.is_valid():
			each.call(t)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _face_lock() -> void:
	var tg: TargetingSystem = scene.targeting
	if tg.has_target():
		var to := tg.get_target_point() - motor.global_position
		motor.command.face_dir = Vector3(to.x, 0, to.z)
		combat.aim_target = tg.current


func _shot(name: String) -> void:
	_skip = 4
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join("combat_" + name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("[combat-demo] %s  player %s HP %.0f  ult %s" % [path, combat.get_state_name(), combat.health.hp,
		combat.ultimate.get_phase_name()])


func _sequence() -> void:
	# start: ranged partner idle, melee partner passive, lock the melee one
	scene.alliance_mode = true  # both partners on one team so they focus the player
	scene._apply_dummy_teams()
	_brain(ranged).enabled = false
	ranged.reset_to(Vector3(30, 0.2, -10))
	_brain(melee).mode = SparringBrain.Mode.PASSIVE
	melee.reset_to(Vector3(0, 0.2, 26.5))
	await _hold(0.8)
	scene.targeting._set_target(melee, "demo")
	await _hold(0.6)
	# 1) light combo L1-L2-L3
	for i in 3:
		motor.command.attack_pressed = true
		await _hold(0.16 if i < 2 else 0.12, func(_t): motor.command.move = Vector3(0, 0, -0.3))
	await _shot("01_combo_finisher")
	await _hold(1.2)
	# 2) melee partner attacks, player guards
	_brain(melee).mode = SparringBrain.Mode.MELEE
	await _hold(2.2, func(_t): motor.command.guard_held = true)
	await _shot("02_guarding")
	motor.command.guard_held = false
	# 3) parry: press F as the partner's swing starts
	var parried := {"done": false}
	var on_atk := func(a: Node3D, _d: AttackDefinition):
		if a == melee and not parried.done:
			parried.done = true
			await get_tree().create_timer(0.05, true, true).timeout
			motor.command.parry_pressed = true
	CombatEvents.attack_started.connect(on_atk)
	await _hold(3.0)
	await _shot("03_after_parry")
	CombatEvents.attack_started.disconnect(on_atk)
	# 4) reflect a pulse shot from the ranged partner
	_brain(melee).mode = SparringBrain.Mode.PASSIVE
	melee.reset_to(Vector3(-25, 0.2, 10))
	ranged.reset_to(Vector3(0, 0.2, 5))
	_brain(ranged).enabled = true
	scene.targeting._set_target(ranged, "demo")
	var reflected := {"done": false}
	await _hold(4.0, func(_t):
		if reflected.done:
			return
		for p in get_tree().get_nodes_in_group(&"projectiles"):
			if (p as Node3D).global_position.distance_to(motor.global_position + Vector3.UP * 2.5) < 7.0:
				motor.command.parry_pressed = true
				reflected.done = true)
	await _shot("04_reflect")
	_brain(ranged).enabled = false
	ranged.reset_to(Vector3(40, 0.2, -30))
	# 5) dash slash on a hovering target (anti-air) — partner brain paused so it holds the hover
	_brain(melee).enabled = false
	motor.reset_to(Vector3(0, 0.2, 30))
	melee.reset_to(Vector3(0, 0.2, 19))
	scene.targeting._set_target(melee, "demo")
	melee.command.jump_pressed = true
	await _hold(1.6, func(_t):
		melee.en = 100.0
		melee.command.ascend = melee.global_position.y < 5.0)
	motor.command.skill_pressed = true
	await _hold(0.38, func(_t):
		melee.en = 100.0
		melee.command.ascend = melee.global_position.y < 5.0)
	await _shot("05_dash_slash_anti_air")
	await _hold(2.0, func(_t): melee.command.ascend = false)
	_brain(melee).enabled = true
	# 6) low HP → ultimate: crown completes, wings unfold
	scene.feedback.focus_mech = motor
	combat.health.take(combat.health.hp - combat.health.max_hp * 0.25)
	await _hold(0.5)
	await _shot("06_crown_ready_low_hp")
	motor.command.ult_pressed = true
	await _hold(0.2)
	await _shot("07_ultimate_windup")
	await _hold(0.4)
	await _shot("08_judgment")
	# 7) final spear on a distant partner
	melee.reset_to(Vector3(0, 0.2, -8))
	scene.targeting._set_target(melee, "demo")
	await _hold(0.4)
	motor.command.skill_pressed = true
	await _hold(0.7)
	await _shot("09_final_spear_charge")
	await _hold(0.75)
	await _shot("10_final_spear_lunge")
	await _hold(6.0)
	await _shot("11_overload")
	var total := 0.0
	var sorted := _frame_times.duplicate()
	sorted.sort()
	for d in _frame_times:
		total += d
	print("[combat-demo] perf (screenshot frames excluded): %d frames, avg %.1f FPS, 1%%-low %.1f FPS, worst %.1f ms, viewport %s, vsync off" % [
		_frame_times.size(), _frame_times.size() / total, 1.0 / sorted[int(sorted.size() * 0.99)], sorted[-1] * 1000.0, get_viewport().get_visible_rect().size])
	print("[combat-demo] log:\n  " + "\n  ".join(log))
	print("[combat-demo] done")
	get_tree().quit(0)
