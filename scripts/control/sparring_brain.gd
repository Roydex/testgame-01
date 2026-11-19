class_name SparringBrain
extends Node
## Scripted sparring partner (陶练机) for phase 2b. NOT an AI: no perception,
## navigation or decision making — it walks straight at its target and loops
## a fixed pattern. It drives the mech exclusively through MechCommand, the
## same path PlayerBrain uses, so it obeys every movement / combat rule.

enum Mode { MELEE, RANGED, PASSIVE, GUARD, PARRY_TRAINER, TRAINING, TRAINING_RANGED }
const MODE_NAMES := ["MELEE", "RANGED", "PASSIVE", "GUARD", "PARRY_TRAINER", "TRAINING", "TRAINING_RANGED"]
const MODE_LABELS := ["全力近战", "全力远程", "静止", "只格挡", "定时招架", "陪练近战", "陪练远程"]

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
	return MODE_LABELS[mode]


## Training pattern state (TRAINING mode).
var _train_step := 0
var _retreat := 0.0
const TRAINING_PATTERN := [1, 2, 1, 3]  # presses per attack: L1 / L1-L2 / L1 / full combo
## Pause between training attacks (s). Telegraph = the windup itself.
@export var training_interval: float = 3.8


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
	var training := mode == Mode.TRAINING or mode == Mode.TRAINING_RANGED
	if use_ultimate and not training and ult and ult.is_ready() and dist < 16.0:
		cmd.ult_pressed = true
	match mode:
		Mode.TRAINING:
			_training(cmd, flat, dist, delta)
		Mode.TRAINING_RANGED:
			if _target_stunned():
				_timer = maxf(_timer, 1.0)
			_ranged(cmd, flat, dist, 4.2)
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
			_ranged(cmd, flat, dist, attack_interval * 0.85)


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


## The target is in hard control: training partners never press on it.
func _target_stunned() -> bool:
	var tc := DamageSystem.get_combat(target)
	return tc != null and (tc.state == CombatStateMachine.CombatState.STAGGER or tc.state == CombatStateMachine.CombatState.OFFBALANCE)


## Practice partner: approaches to ~5 m, waits, performs ONE readable
## attack from a fixed rotating pattern, then backs off. Never follows up
## while the target is staggered, never uses the dash slash or ultimate.
func _training(cmd: MechCommand, flat: Vector3, dist: float, delta: float) -> void:
	var dir := flat.normalized()
	if _retreat > 0.0:
		_retreat -= delta
		cmd.move = -dir * 0.7
		return
	if _combo_presses > 0:
		_press_gap -= delta
		if _press_gap <= 0.0:
			cmd.attack_pressed = true
			_combo_presses -= 1
			_press_gap = 0.3
			if _combo_presses == 0:
				_retreat = 1.4
		return
	if dist > 4.8:
		cmd.move = dir * 0.65  # walk in at a readable pace (stops inside lance reach)
		return
	if dist < 2.8:
		cmd.move = -dir * 0.4
	else:
		cmd.move = dir.cross(Vector3.UP) * _strafe * 0.25
	if _target_stunned():
		_timer = maxf(_timer, 1.2)
		return
	if _timer <= 0.0:
		_combo_presses = TRAINING_PATTERN[_train_step % TRAINING_PATTERN.size()]
		_train_step += 1
		_press_gap = 0.0
		_timer = training_interval


func _ranged(cmd: MechCommand, flat: Vector3, dist: float, interval: float) -> void:
	var dir := flat.normalized()
	if dist < ranged_min:
		cmd.move = -dir
	elif dist > ranged_max:
		cmd.move = dir
	else:
		cmd.move = dir.cross(Vector3.UP) * _strafe * 0.6
	if _timer <= 0.0 and dist < 60.0:
		cmd.attack_pressed = true
		_timer = interval
