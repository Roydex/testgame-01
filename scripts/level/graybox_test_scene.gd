extends Node3D
## Playable movement grey-box. Spawns the player mech, camera rig, targeting
## and debug HUD into the code-built arena.
##
## Command-line (after `--`):
##   --autopilot   run a scripted showcase, save screenshots to
##                 tests/logs/, print a state trace, then quit.

var motor: MechMotor
var rig: CameraRig
var targeting: TargetingSystem
var brain: PlayerBrain
var hud: DebugHud
var combat: CombatStateMachine
var profile_index: int = 0
var shooters_on: bool = false
var combat_hud: CombatHud
var pause_menu: PauseMenu
var feedback: CombatFeedback
var dummies: Array[MechMotor] = []
var alliance_mode: bool = false
## Practice mode (default): nobody dies (HP floor 1), partners regenerate,
## the ultimate has unlimited uses, partners use the readable TRAINING
## pattern. F12 switches to match rules (death, once-per-match ultimate,
## full-aggression partners).
var practice_mode: bool = true


func _ready() -> void:
	GrayboxBuilder.build(self)
	_spawn_player(1)
	_spawn_dummies()
	set_practice(true)
	if "--autopilot" in OS.get_cmdline_user_args():
		var ap := preload("res://scripts/debug/autopilot.gd").new()
		ap.name = "Autopilot"
		add_child(ap)
		ap.run(self)
	elif "--combat-demo" in OS.get_cmdline_user_args():
		var cd := preload("res://scripts/debug/combat_autopilot.gd").new()
		cd.name = "CombatAutopilot"
		add_child(cd)
		cd.run(self)
	elif "--pause-shot" in OS.get_cmdline_user_args():
		_pause_shot.call_deferred()
	elif "--practice-shot" in OS.get_cmdline_user_args():
		_practice_shot.call_deferred()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The player's mech (PALE SERAPH here; the skill lab overrides it).
func _create_player_motor(index: int) -> MechMotor:
	var p := MechFactory.load_profile(index)
	return MechFactory.create_mech(p, 0, MechFactory.COLORS[index % MechFactory.COLORS.size()], true,
		load(MechFactory.COMBAT_SERAPH), &"seraph")


func _spawn_player(index: int) -> void:
	profile_index = index
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	hud = DebugHud.new()
	hud.name = "DebugHud"
	add_child(hud)
	combat_hud = CombatHud.new()
	combat_hud.name = "CombatHud"
	add_child(combat_hud)
	feedback = CombatFeedback.new()
	feedback.name = "CombatFeedback"
	add_child(feedback)
	feedback.rig = rig
	attach_player(_create_player_motor(index), GrayboxBuilder.POINTS.spawn)

	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.mode_text_provider = func() -> String:
		return "当前：%s" % ("练习模式（不会阵亡 · 大招不限次数）" if practice_mode else "实战模式（会阵亡 · 大招每局 1 次）")
	pause_menu.restart_requested.connect(func(): get_tree().reload_current_scene())
	pause_menu.practice_toggle_requested.connect(func():
		set_practice(not practice_mode)
		combat_hud.callout("练习模式" if practice_mode else "实战模式"))


## Puts `m` in as the player: lock-on, camera, input brain and HUDs follow it.
## Used at spawn and when the skill lab swaps mechs.
func attach_player(m: MechMotor, at: Vector3) -> void:
	motor = m
	motor.name = "Player"
	motor.position = at
	add_child(motor)
	combat = motor.get_node("CombatStateMachine")
	targeting = TargetingSystem.new()
	targeting.name = "Targeting"
	motor.add_child(targeting)
	targeting.setup(motor, rig.camera)
	rig.setup(motor, targeting)
	brain = PlayerBrain.new()
	brain.name = "PlayerBrain"
	motor.add_child(brain)
	brain.setup(motor, rig, targeting)
	hud.setup(motor, combat, targeting, rig)
	combat_hud.setup(motor, targeting)
	feedback.focus_mech = motor


## Two scripted sparring partners (陶练机): a melee one with the full PALE
## SERAPH kit (incl. its ultimate) and a ranged one. F8 toggles them between
## separate teams (FFA-like) and one team (alliance-like).
func _spawn_dummies() -> void:
	var specs := [
		["Sparring_Melee", MechFactory.COMBAT_SERAPH, &"seraph", Color(0.85, 0.75, 0.6), Vector3(0, 0.2, 5), SparringBrain.Mode.MELEE, 1],
		["Sparring_Ranged", MechFactory.COMBAT_SPARRING_RANGED, &"generic", Color(0.45, 0.5, 0.3), Vector3(20, 0.2, 0), SparringBrain.Mode.RANGED, 2],
	]
	for s in specs:
		var d := MechFactory.create_mech(MechFactory.load_profile(1 if s[2] == &"seraph" else 4), s[6], s[3], true, load(s[1]), s[2])
		d.name = s[0]
		d.position = s[4]
		d.add_to_group(&"lock_targets")
		add_child(d)
		var b := SparringBrain.new()
		b.name = "SparringBrain"
		b.mode = s[5]
		d.add_child(b)
		b.setup(d)
		dummies.append(d)
	_apply_dummy_teams()


func set_practice(on: bool) -> void:
	practice_mode = on
	# practice partners work together on the player (F8 still toggles)
	alliance_mode = on
	_apply_dummy_teams()
	var all: Array[MechMotor] = [motor]
	all.append_array(dummies)
	for m in all:
		var c := m.get_node(^"CombatStateMachine") as CombatStateMachine
		c.health.min_hp = 1.0 if on else 0.0
		c.health.regen_rate = 80.0 if on and m != motor else 0.0
		if c.ultimate:
			c.ultimate.unlimited_uses = on
	if dummies.size() >= 2:
		(dummies[0].get_node(^"SparringBrain") as SparringBrain).mode = SparringBrain.Mode.TRAINING if on else SparringBrain.Mode.MELEE
		(dummies[1].get_node(^"SparringBrain") as SparringBrain).mode = SparringBrain.Mode.TRAINING_RANGED if on else SparringBrain.Mode.RANGED
	if combat_hud:
		combat_hud.set_mode_banner(_banner())


func _banner() -> String:
	var m0 := (dummies[0].get_node(^"SparringBrain") as SparringBrain).get_mode_name() if dummies.size() > 0 else "-"
	var m1 := (dummies[1].get_node(^"SparringBrain") as SparringBrain).get_mode_name() if dummies.size() > 1 else "-"
	if practice_mode:
		return "练习模式（不会阵亡 · 大招不限次数）   近战陪练：%s   远程陪练：%s   %s   [F12 切换实战  F5 回满]" % [m0, m1, "联盟" if alliance_mode else "乱斗"]
	return "实战模式（会阵亡 · 大招每局 1 次）   近战：%s   远程：%s   %s   [F12 切换练习  F7 重开]" % [m0, m1, "联盟" if alliance_mode else "乱斗"]


func _apply_dummy_teams() -> void:
	if dummies.size() >= 2:
		dummies[0].team_id = 1
		dummies[1].team_id = 1 if alliance_mode else 2


func cycle_profile() -> void:
	## Swap the movement profile + colour in place (keeps position / state).
	profile_index = (profile_index + 1) % MechFactory.PROFILES.size()
	motor.set_profile(MechFactory.load_profile(profile_index))
	var vis := motor.get_node_or_null("Visual") as MechVisual
	if vis:
		vis.queue_free()
		var nv := MechVisual.new()
		nv.name = "Visual"
		motor.add_child(nv)
		nv.setup(motor, MechFactory.COLORS[profile_index])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_toggle_hud"):
		hud.toggle_panel()
	elif event.is_action_pressed(&"debug_cycle_profile"):
		cycle_profile()
	elif event.is_action_pressed(&"debug_stagger"):
		combat.apply_stagger(0.6, -motor.get_forward() * 8.0 + Vector3.UP * 2.0)
	elif event.is_action_pressed(&"debug_action"):
		combat.start_action(0.8)
	elif event.is_action_pressed(&"debug_reset"):
		motor.reset_to(GrayboxBuilder.POINTS.spawn)
		combat.restore_full()
		if practice_mode:
			for d in dummies:
				(d.get_node(^"CombatStateMachine") as CombatStateMachine).restore_full()
		rig.snap()
		combat_hud.callout("已回满：HP / EN / 大招")
	elif event.is_action_pressed(&"debug_practice"):
		set_practice(not practice_mode)
		combat_hud.callout("练习模式" if practice_mode else "实战模式")
	elif event.is_action_pressed(&"debug_ranged_mode"):
		var rb := dummies[1].get_node(^"SparringBrain") as SparringBrain
		var cycle := [SparringBrain.Mode.TRAINING_RANGED, SparringBrain.Mode.RANGED, SparringBrain.Mode.PASSIVE]
		rb.mode = cycle[(cycle.find(rb.mode) + 1) % cycle.size()]
		combat_hud.set_mode_banner(_banner())
		combat_hud.callout("远程陪练机：%s" % rb.get_mode_name())
	elif event.is_action_pressed(&"debug_toggle_shooters"):
		shooters_on = not shooters_on
		TestProjectile.reset_stats()
		for t in get_tree().get_nodes_in_group(&"lock_targets"):
			if t is TestTarget and t.shooter:
				t.shooting_enabled = shooters_on
	elif event.is_action_pressed(&"debug_kill_target"):
		if targeting.has_target() and targeting.current.has_method(&"kill"):
			targeting.current.call(&"kill")
		elif targeting.has_target():
			var tc := DamageSystem.get_combat(targeting.current)
			if tc:
				tc.health.take(tc.health.hp)
	elif event.is_action_pressed(&"debug_restart"):
		get_tree().reload_current_scene()
	elif event.is_action_pressed(&"debug_dummy_teams"):
		alliance_mode = not alliance_mode
		_apply_dummy_teams()
		combat_hud.set_mode_banner(_banner())
		combat_hud.callout("陶练机阵营：%s" % ("同阵营（联盟）" if alliance_mode else "互相敌对（乱斗）"))
	elif event.is_action_pressed(&"debug_dummy_mode"):
		var b := dummies[0].get_node(^"SparringBrain") as SparringBrain
		var mcycle := [SparringBrain.Mode.TRAINING, SparringBrain.Mode.MELEE, SparringBrain.Mode.PASSIVE,
			SparringBrain.Mode.GUARD, SparringBrain.Mode.PARRY_TRAINER]
		b.mode = mcycle[(mcycle.find(b.mode) + 1) % mcycle.size()]
		combat_hud.set_mode_banner(_banner())
		combat_hud.callout("近战陪练机：%s" % b.get_mode_name())
	elif event.is_action_pressed(&"debug_low_hp"):
		combat.health.take(maxf(combat.health.hp - combat.health.max_hp * 0.29, 0.0))


## Debug: let the default practice scene run untouched, save screenshots of
## the training partner at work, then quit (`-- --practice-shot`).
func _practice_shot() -> void:
	brain.enabled = false
	targeting._set_target(dummies[0], "shot")
	var dir := ProjectSettings.globalize_path("res://docs/screenshots")
	for i in 3:
		await get_tree().create_timer(2.7 if i == 0 else 2.2).timeout
		var to := dummies[0].global_position - motor.global_position
		motor.command.face_dir = Vector3(to.x, 0, to.z)
		combat.aim_target = dummies[0]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("practice_%d.png" % i))
		print("[practice-shot] %d player HP %.0f state %s / partner %s" % [i, combat.health.hp, combat.get_state_name(),
			(dummies[0].get_node(^"CombatStateMachine") as CombatStateMachine).get_state_name()])
	get_tree().quit()


## Debug: open the pause menu in the real window, screenshot it, check the
## mouse capture round trip, then quit (`-- --pause-shot`).
func _pause_shot() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().create_timer(2.5).timeout
	var before := Input.mouse_mode
	pause_menu.open()
	pause_menu._controls.visible = true
	await get_tree().create_timer(0.3, true).timeout
	var during := Input.mouse_mode
	var pos := motor.global_position
	await get_tree().create_timer(1.0, true).timeout
	var frozen := motor.global_position.is_equal_approx(pos)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://docs/screenshots/pause_menu.png"))
	pause_menu.resume()
	await get_tree().create_timer(0.3).timeout
	print("[pause-shot] mouse before %d, during pause %d, after resume %d (0 visible, 2 captured); tree paused now %s; world frozen while paused %s" % [
		before, during, Input.mouse_mode, get_tree().paused, frozen])
	get_tree().quit()
