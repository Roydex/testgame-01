class_name SparringBrain
extends Node
## Scripted sparring partner (陶练机) for phase 2b. NOT an AI: no perception,
## navigation or decision making — it walks straight at its target and loops
## a fixed pattern. It drives the mech exclusively through MechCommand, the
## same path PlayerBrain uses, so it obeys every movement / combat rule.

enum Mode { MELEE, RANGED, PASSIVE, GUARD, PARRY_TRAINER }
const MODE_NAMES := ["MELEE", "RANGED", "PASSIVE", "GUARD", "PARRY_TRAINER"]

@export var mode: Mode = Mode.MELEE
## Seconds between pattern loops.
@export var attack_interval: float = 2.6
@export var melee_range: float = 4.5
@export var ranged_min: float = 20.0
@export var ranged_max: float = 30.0
@export var use_ultimate: bool = true

var motor: MechMotor
var combat: CombatStateMachine
var target: Node3D
var enabled: bool = true
var _timer: float = 1.5
var _combo_presses: int = 0
var _press_gap: float = 0.0
var _strafe := 1.0
var _strafe_timer := 0.0


func setup(p_motor: MechMotor) -> void:
	motor = p_motor
	combat = motor.get_node(^"CombatStateMachine") as CombatStateMachine
	process_physics_priority = -10


func get_mode_name() -> String:
	return MODE_NAMES[mode]


func _pick_target() -> void:
	if target and TeamRules.can_damage(motor, target):
		return
	target = null
	var best := INF
	for t in TeamRules.get_valid_targets(motor, &"mechs"):
		var d := motor.global_position.distance_to(t.global_position)
		if d < best:
			best = d
			target = t


func _physics_process(delta: float) -> void:
	if not enabled or motor == null or combat.is_dead():
		return
	var cmd := motor.command
	cmd.move = Vector3.ZERO
	cmd.guard_held = false
	cmd.ascend = false
	cmd.descend = false
	_pick_target()
	combat.aim_target = target
	if target == null:
		return
	var to := target.global_position - motor.global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var dist := flat.length()
	cmd.face_dir = flat
	_timer -= delta
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(1.5, 3.0)
		_strafe = -_strafe
	# follow the target's altitude a little so it stays reachable
	if to.y > 3.0 and motor.en > 30.0:
		cmd.ascend = true
		if motor.is_grounded_state():
			cmd.jump_pressed = true
	elif to.y < -2.0:
		cmd.descend = true
	var ult := combat.ultimate
	if use_ultimate and ult and ult.is_ready() and dist < 16.0:
		cmd.ult_pressed = true
	match mode:
		Mode.PASSIVE:
			pass
		Mode.GUARD:
			cmd.guard_held = true
		Mode.PARRY_TRAINER:
			# parries on a fixed rhythm so the player can practise reading it
			if _timer <= 0.0:
				cmd.parry_pressed = true
				_timer = 1.2
		Mode.MELEE:
			_melee(cmd, flat, dist, delta)
		Mode.RANGED:
			_ranged(cmd, flat, dist)


func _melee(cmd: MechCommand, flat: Vector3, dist: float, delta: float) -> void:
	var judging := combat.ultimate and combat.ultimate.in_judgment()
	if judging and dist > 10.0 and combat.ultimate.spear_charges_left > 0 and _timer <= 0.0:
		cmd.skill_pressed = true  # 终审之矛
		_timer = attack_interval
		return
	if dist > melee_range:
		cmd.move = flat.normalized()
		if dist > 10.0 and dist < 18.0 and _timer <= 0.0 and combat.get_cooldown(&"seraph_dash_slash") <= 0.0:
			cmd.skill_pressed = true  # 瞬时突进斩 to close in
			_timer = attack_interval
		return
	cmd.move = flat.normalized().cross(Vector3.UP) * _strafe * 0.3
	if _combo_presses > 0:
		_press_gap -= delta
		if _press_gap <= 0.0:
			cmd.attack_pressed = true
			_combo_presses -= 1
			_press_gap = 0.28
	elif _timer <= 0.0:
		_combo_presses = 3
		_press_gap = 0.0
		_timer = attack_interval


func _ranged(cmd: MechCommand, flat: Vector3, dist: float) -> void:
	var dir := flat.normalized()
	if dist < ranged_min:
		cmd.move = -dir
	elif dist > ranged_max:
		cmd.move = dir
	else:
		cmd.move = dir.cross(Vector3.UP) * _strafe * 0.6
	if _timer <= 0.0 and dist < 60.0:
		cmd.attack_pressed = true
		_timer = attack_interval * 0.85
