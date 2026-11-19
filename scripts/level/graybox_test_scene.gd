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


func _ready() -> void:
	GrayboxBuilder.build(self)
	_spawn_player(0)
	if "--autopilot" in OS.get_cmdline_user_args():
		var ap := preload("res://scripts/debug/autopilot.gd").new()
		ap.name = "Autopilot"
		add_child(ap)
		ap.run(self)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _spawn_player(index: int) -> void:
	profile_index = index
	var p := MechFactory.load_profile(index)
	motor = MechFactory.create_mech(p, 0, MechFactory.COLORS[index % MechFactory.COLORS.size()])
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
