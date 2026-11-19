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
var feedback: CombatFeedback
var dummies: Array[MechMotor] = []
var alliance_mode: bool = false


func _ready() -> void:
	GrayboxBuilder.build(self)
	_spawn_player(1)
	_spawn_dummies()
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
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _spawn_player(index: int) -> void:
	profile_index = index
	var p := MechFactory.load_profile(index)
	motor = MechFactory.create_mech(p, 0, MechFactory.COLORS[index % MechFactory.COLORS.size()], true,
		load(MechFactory.COMBAT_SERAPH), &"seraph")
	motor.name = "Player"
	motor.position = GrayboxBuilder.POINTS.spawn
	add_child(motor)
	combat = motor.get_node("CombatStateMachine")

	targeting = TargetingSystem.new()
	targeting.name = "Targeting"
	motor.add_child(targeting)

	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)

	targeting.setup(motor, rig.camera)
	rig.setup(motor, targeting)

	brain = PlayerBrain.new()
	brain.name = "PlayerBrain"
	motor.add_child(brain)
	brain.setup(motor, rig, targeting)

	hud = DebugHud.new()
	hud.name = "DebugHud"
	add_child(hud)
	hud.setup(motor, combat, targeting, rig)

	combat_hud = CombatHud.new()
	combat_hud.name = "CombatHud"
	add_child(combat_hud)
	combat_hud.setup(motor, targeting)

	feedback = CombatFeedback.new()
	feedback.name = "CombatFeedback"
	add_child(feedback)
	feedback.rig = rig
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
		rig.snap()
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
		combat_hud.callout("陶练机阵营：%s" % ("同阵营（联盟）" if alliance_mode else "互相敌对（乱斗）"))
	elif event.is_action_pressed(&"debug_dummy_mode"):
		var b := dummies[0].get_node(^"SparringBrain") as SparringBrain
		b.mode = (b.mode + 1) % SparringBrain.MODE_NAMES.size()
		combat_hud.callout("近战陶练机模式：%s" % b.get_mode_name())
	elif event.is_action_pressed(&"debug_low_hp"):
		combat.health.take(maxf(combat.health.hp - combat.health.max_hp * 0.29, 0.0))
