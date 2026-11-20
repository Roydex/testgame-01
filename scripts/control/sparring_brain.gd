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
# --- phase 3a kit pattern (HELLFANG / VERDANT / AZURE partners)
var _kit_step := 0
## Current scripted action: [kind, frames_left].
var _act: Array = []


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
	cmd.attack_held = false
	cmd.skill_held = false
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
		elif not motor.hover_engaged:
			cmd.hover_lock_request = 1  # stay up there once level with the target
	elif to.y < -2.0:
		cmd.descend = true
		if motor.is_air_state() and not motor.fast_descent:
			cmd.descend_pressed = true  # tap-descend back down
	var ult := combat.ultimate
	var training := mode == Mode.TRAINING or mode == Mode.TRAINING_RANGED
	if use_ultimate and not training and ult and ult.is_ready() and dist < 16.0:
		cmd.ult_pressed = true
	if _uses_kit_pattern() and (mode == Mode.TRAINING or mode == Mode.MELEE or mode == Mode.TRAINING_RANGED or mode == Mode.RANGED):
		_kit_pattern(cmd, flat, dist, delta, training)
		return
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


## Phase 3a partners (any mech with a kit or a hold skill) run one generic
## readable loop built from their profile: keep a preferred range, then
## perform the next action of a fixed cycle. Still a script, not an AI.
func _uses_kit_pattern() -> bool:
	# PALE SERAPH's mirror heat kit (round 6) is not a phase-3a kit: it keeps
	# its own melee / training script
	var k := combat.profile.kit
	return (k != null and not k is MirrorConfig) or combat.profile.skill_hold != null


func _kit_actions() -> Array[StringName]:
	var p := combat.profile
	var a: Array[StringName] = [&"primary"]
	if p.skill: a.append(&"skill")
	a.append(&"primary")
	if p.skill_hold: a.append(&"skill_hold")
	if p.attack_hold: a.append(&"attack_hold")
	if p.charge_attack: a.append(&"charge")
	return a


func _preferred_range() -> Vector2:
	var p := combat.profile
	if p.light_combo:
		return Vector2(2.8, 4.6)
	var r := p.ranged.projectile_range if p.ranged else 30.0
	return Vector2(clampf(r * 0.25, 8.0, 18.0), clampf(r * 0.45, 12.0, 28.0))


func _kit_pattern(cmd: MechCommand, flat: Vector3, dist: float, _delta: float, training: bool) -> void:
	var dir := flat.normalized()
	var band := _preferred_range()
	if dist > band.y:
		cmd.move = dir * (0.65 if training else 1.0)
	elif dist < band.x:
		cmd.move = -dir * 0.5
	else:
		cmd.move = dir.cross(Vector3.UP) * _strafe * 0.3
	if not _act.is_empty():
		_run_action(cmd)
		return
	if combat.is_aiming_placement():
		cmd.attack_pressed = true  # scripts never hand-mark: confirm at once (auto-call on the target)
		return
	if training and _target_stunned():
		_timer = maxf(_timer, 1.2)
		return
	# a melee kit closes long gaps with its skill (HELLFANG grapple)
	if combat.profile.light_combo and dist > 9.0 and dist < 24.0 and combat.profile.skill \
			and combat.get_cooldown(combat.profile.skill.id) <= 0.0 and _timer <= 0.0:
		_act = [&"skill", 2]
		_timer = training_interval if training else attack_interval * 0.6
		return
	if _timer > 0.0 or dist > band.y + 6.0:
		return
	var acts := _kit_actions()
	var kind: StringName = acts[_kit_step % acts.size()]
	_kit_step += 1
	match kind:
		&"primary":
			_act = [&"primary", 3 if combat.profile.light_combo else 2]
		&"skill":
			_act = [&"skill", 2]
		&"skill_hold":
			_act = [&"skill_hold", 26]
		&"attack_hold":
			_act = [&"attack_hold", 26]
		&"charge":
			_act = [&"charge", int(combat.profile.charge_time * 0.8 * 60.0)]
	_timer = training_interval if training else attack_interval * 0.6


func _run_action(cmd: MechCommand) -> void:
	var kind: StringName = _act[0]
	var left: int = _act[1]
	match kind:
		&"primary":
			_press_gap -= 1.0 / 60.0
			if _press_gap <= 0.0:
				cmd.attack_pressed = true
				cmd.attack_held = true
				_press_gap = 0.32
				left -= 1
		&"skill":
			cmd.skill_pressed = left == 2
			cmd.skill_held = false
			left -= 1
		&"skill_hold":
			cmd.skill_pressed = left == 26
			cmd.skill_held = true
			left -= 1
		&"attack_hold":
			cmd.attack_pressed = left == 26
			cmd.attack_held = true
			left -= 1
		&"charge":
			cmd.guard_held = true
			left -= 1
	_act[1] = left
	if left <= 0:
		_act = []
		_press_gap = 0.0
