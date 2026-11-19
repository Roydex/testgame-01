class_name MechMotor
extends CharacterBody3D
## Shared Ground-Air Hybrid movement for every mech (player and AI).
##
## Layering:
##   Brain (PlayerBrain / AIBrain / test script) -> MechCommand
##   Combat / skills -> MovementModifier + apply_impulse()  (never velocity)
##   MechMotor -> owns velocity, motion state, EN, collision
##   Visual / animation -> reads motor state only (cannot block control)
##
## Uses MOTION_MODE_GROUNDED at all times: hover is a vertical-thrust state,
## not a FLOATING motion mode, so floor detection and landing stay intact.
## Origin of the body is at the feet.

signal motion_state_changed(old_state: int, new_state: int)
signal landed(impact_speed: float, hard: bool)
signal took_off
signal dashed(in_air: bool)
signal en_exhausted
signal en_changed(value: float, max_value: float)

enum MotionState { GROUNDED, GROUND_DASH, TAKEOFF, AIRBORNE, HOVER, AIR_DASH, FALLING, LANDING }

const STATE_NAMES := ["GROUNDED", "GROUND_DASH", "TAKEOFF", "AIRBORNE", "HOVER", "AIR_DASH", "FALLING", "LANDING"]
const BODY_HEIGHT := 4.0
const INPUT_BUFFER := 0.12
const COYOTE_TIME := 0.1
const STUCK_TIME := 0.4

@export var profile: MechMovementProfile
## Team for hostility checks (see TeamRules). 0 = player in prototype.
@export var team_id: int = 0
## When true every state transition is appended to transition_log (tests/debug).
@export var record_transitions: bool = false

var state: int = MotionState.FALLING
var state_time: float = 0.0
var en: float = 100.0
## Feet height when the mech last left the ground; thrust ceiling is relative to it.
var takeoff_height: float = 0.0
## True once the pilot has used thrust in this flight; releasing ascend then hovers.
var hover_engaged: bool = false
var active_descent: bool = false
var air_time: float = 0.0
var last_impact_speed: float = 0.0
var transition_log: Array[String] = []
## Latest intent written by a brain. The motor copies it each physics tick.
var command: MechCommand = MechCommand.new()

var _cmd: MechCommand = MechCommand.new()
var _modifiers: Dictionary = {}
var _m_speed := 1.0
var _m_accel := 1.0
var _m_turn := 1.0
var _m_gravity := 1.0
var _m_block_move := false
var _m_block_jump := false
var _m_block_dash := false
var _m_block_thrust := false
var _m_block_facing := false
var _m_forced := false
var _forced_mod: MovementModifier
var _m_en_cost := 1.0
var _m_block_regen := false
var _hitstop := 0.0

var _jump_buffer := 0.0
var _dash_buffer := 0.0
var _dash_cooldown := 0.0
var _dash_dir := Vector3.FORWARD
var _regen_timer := 0.0
var _landing_timer := 0.0
var _coyote := 0.0
var _stuck_timer := 0.0
var _stuck_ref_y := 0.0
var _bounds: MapBounds
var _last_safe_position := Vector3.ZERO
var last_collisions: PackedStringArray = []


func _ready() -> void:
	if profile == null:
		profile = MechMovementProfile.new()
	motion_mode = MOTION_MODE_GROUNDED
	floor_max_angle = deg_to_rad(46.0)
	floor_stop_on_slope = true
	floor_constant_speed = true
	floor_snap_length = 0.6
	en = profile.max_en
	_last_safe_position = global_position
	takeoff_height = global_position.y
	add_to_group(&"mechs")
	_find_bounds.call_deferred()


func _find_bounds() -> void:
	_bounds = get_tree().get_first_node_in_group(&"map_bounds") as MapBounds


# --------------------------------------------------------------------------
# Public API
# --------------------------------------------------------------------------

func set_profile(p: MechMovementProfile) -> void:
	profile = p
	en = minf(en, profile.max_en)


func add_modifier(mod: MovementModifier) -> void:
	_modifiers[mod.id] = mod
	_recompute_modifiers()


func remove_modifier(id: StringName) -> void:
	if _modifiers.erase(id):
		_recompute_modifiers()


## Re-read modifier fields after a caller mutated one in place (e.g. a
## lunge toggling `forced`).
func refresh_modifiers() -> void:
	_recompute_modifiers()


func has_modifier(id: StringName) -> bool:
	return _modifiers.has(id)


func get_modifier_descriptions() -> PackedStringArray:
	var out: PackedStringArray = []
	for m: MovementModifier in _modifiers.values():
		out.append(m.describe())
	return out


## External push (knockback, recoil). Adds to velocity; the motor's own
## steering then decays it. Interrupts dashes.
func apply_impulse(impulse: Vector3) -> void:
	velocity += impulse
	if state == MotionState.AIR_DASH:
		_set_state(MotionState.FALLING)
	elif state == MotionState.GROUND_DASH:
		_set_state(MotionState.GROUNDED)
	if impulse.y > 0.5 and is_grounded_state():
		takeoff_height = global_position.y
		_set_state(MotionState.AIRBORNE)


func reset_to(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	en = profile.max_en
	hover_engaged = false
	takeoff_height = pos.y
	_set_state(MotionState.FALLING)


func is_grounded_state() -> bool:
	return state == MotionState.GROUNDED or state == MotionState.GROUND_DASH or state == MotionState.LANDING


func is_air_state() -> bool:
	return not is_grounded_state()


func get_state_name() -> String:
	return STATE_NAMES[state]


func get_horizontal_velocity() -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z)


func get_forward() -> Vector3:
	return -global_basis.z


func get_ascent_ceiling() -> float:
	var c := takeoff_height + profile.max_ascent_height
	if _bounds:
		c = minf(c, _bounds.ceiling_y - BODY_HEIGHT)
	return c


func get_height_above_ground(max_dist: float = 500.0) -> float:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.1
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * max_dist, collision_mask)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return INF
	return global_position.y - (hit.position as Vector3).y


func can_afford(cost: float) -> bool:
	return en >= cost


## Spend EN for an action (skills, guard). Returns false (and spends
## nothing) when there is not enough.
func consume_en(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if en < amount:
		return false
	_spend(amount)
	return true


## Local hitstop: this mech freezes (no movement, timers paused) for `t`.
func apply_hitstop(t: float) -> void:
	_hitstop = maxf(_hitstop, t)


func in_hitstop() -> bool:
	return _hitstop > 0.0


func get_en_cost_mult() -> float:
	return _m_en_cost


func get_lock_point() -> Vector3:
	return global_position + Vector3.UP * 2.2


func is_alive() -> bool:
	var h := get_node_or_null(^"Health") as Health
	return h == null or not h.dead


# --------------------------------------------------------------------------
# Main loop
# --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _hitstop > 0.0:
		_hitstop -= delta
		return  # frozen; buffered command edges are kept for after the stop
	_tick_modifiers(delta)
	_cmd.copy_from(command)
	command.clear_edges()
	if _m_block_move:
		_cmd.move = Vector3.ZERO
	_cmd.move.y = 0.0
	if _cmd.move.length_squared() > 1.0:
		_cmd.move = _cmd.move.normalized()

	_jump_buffer = INPUT_BUFFER if _cmd.jump_pressed else maxf(_jump_buffer - delta, 0.0)
	_dash_buffer = INPUT_BUFFER if _cmd.dash_pressed else maxf(_dash_buffer - delta, 0.0)
	_dash_cooldown = maxf(_dash_cooldown - delta, 0.0)
	state_time += delta

	if _m_forced:
		_update_forced(delta)
	else:
		match state:
			MotionState.GROUNDED, MotionState.LANDING:
				_update_ground(delta)
			MotionState.GROUND_DASH:
				_update_ground_dash(delta)
			MotionState.AIR_DASH:
				_update_air_dash(delta)
			_:
				_update_air(delta)

	_enforce_ceiling()
	_update_facing(delta)

	floor_snap_length = 0.6 if is_grounded_state() else 0.0
	var vy_before := velocity.y
	move_and_slide()
	_post_move(vy_before, delta)
	_regen(delta)
	_enforce_bounds()


# --------------------------------------------------------------------------
# Motion correction (lunges)
# --------------------------------------------------------------------------

func _update_forced(delta: float) -> void:
	velocity = _forced_mod.forced_velocity
	if is_air_state():
		air_time += delta
	if velocity.y > 0.5 and is_grounded_state():
		takeoff_height = global_position.y
		hover_engaged = false
		air_time = 0.0
		_set_state(MotionState.AIRBORNE)
	elif state == MotionState.GROUND_DASH or state == MotionState.AIR_DASH:
		_set_state(MotionState.FALLING if is_air_state() else MotionState.GROUNDED)
	# never let a lunge carry the mech above its thrust ceiling
	if velocity.y > 0.0 and global_position.y >= get_ascent_ceiling():
		velocity.y = 0.0


# --------------------------------------------------------------------------
# Ground
# --------------------------------------------------------------------------

func _update_ground(delta: float) -> void:
	var max_speed := profile.ground_max_speed * _m_speed
	if state == MotionState.LANDING:
		max_speed *= profile.landing_speed_mult
	var h := _steer(get_horizontal_velocity(), _cmd.move * max_speed,
		profile.ground_accel * _m_accel, profile.ground_decel, profile.ground_turn_grip,
		profile.overspeed_decel, delta)
	velocity = Vector3(h.x, 0.0, h.z)

	if state == MotionState.LANDING:
		_landing_timer -= delta
		if _landing_timer <= 0.0:
			_set_state(MotionState.GROUNDED)
		return

	if _jump_buffer > 0.0 and not _m_block_jump:
		_do_jump()
	elif _dash_buffer > 0.0 and _can_dash(profile.ground_dash_cost * _m_en_cost):
		_start_dash(false)


func _update_ground_dash(delta: float) -> void:
	velocity = _dash_dir * profile.ground_dash_speed * maxf(_m_speed, 0.5)
	if _m_block_move:
		_set_state(MotionState.GROUNDED)
		return
	if _jump_buffer > 0.0 and not _m_block_jump:
		_do_jump()  # dash-jump keeps the dash momentum
		return
	if state_time >= profile.ground_dash_duration:
		_set_state(MotionState.GROUNDED)
	# leaving a ledge mid-dash is handled in _post_move


func _do_jump() -> void:
	_jump_buffer = 0.0
	velocity.y = profile.jump_velocity
	takeoff_height = global_position.y
	hover_engaged = false
	active_descent = false
	air_time = 0.0
	_set_state(MotionState.TAKEOFF)
	took_off.emit()


# --------------------------------------------------------------------------
# Air
# --------------------------------------------------------------------------

func _update_air(delta: float) -> void:
	air_time += delta
	var control := 1.0 if en > 0.0 else profile.exhausted_air_control
	var h := _steer(get_horizontal_velocity(), _cmd.move * profile.air_max_speed * _m_speed,
		profile.air_accel * _m_accel * control, profile.air_decel * control,
		profile.air_turn_grip * control, profile.overspeed_decel * 0.5, delta)
	velocity.x = h.x
	velocity.z = h.z

	if _dash_buffer > 0.0 and _can_dash(profile.air_dash_cost * _m_en_cost):
		_start_dash(true)
		return

	var g := profile.gravity * _m_gravity
	if state == MotionState.TAKEOFF:
		velocity.y -= g * delta
		if state_time >= profile.takeoff_time:
			_set_state(MotionState.AIRBORNE if velocity.y > 0.0 else MotionState.FALLING)
		return

	var thrust_ok := en > 0.0 and not _m_block_thrust
	active_descent = false
	if _cmd.ascend and thrust_ok:
		hover_engaged = true
		var room := get_ascent_ceiling() - global_position.y
		if room > 0.05:
			var rate := profile.ascend_accel if velocity.y >= 0.0 else profile.ascend_accel + profile.hover_brake
			velocity.y = move_toward(velocity.y, profile.ascend_speed, rate * delta)
			# brake into the ceiling instead of overshooting it
			velocity.y = minf(velocity.y, _approach_speed(room, profile.hover_brake))
			_spend(profile.ascend_cost_per_sec * delta)
			_set_state(MotionState.AIRBORNE)
		else:
			velocity.y = minf(move_toward(velocity.y, 0.0, profile.hover_brake * delta), 0.0)
			_spend(profile.hover_cost_per_sec * delta)
			_set_state(MotionState.HOVER)
	elif _cmd.descend and thrust_ok:
		# controlled descent: thrusters hold the sink rate at descend_speed
		# (no EN cost). With EN exhausted this branch is skipped -> free fall.
		active_descent = true
		velocity.y = move_toward(velocity.y, -profile.descend_speed, maxf(profile.descend_accel, g) * delta)
		_set_state(MotionState.FALLING)
	elif hover_engaged and thrust_ok:
		velocity.y = move_toward(velocity.y, 0.0, profile.hover_brake * delta)
		_spend(profile.hover_cost_per_sec * delta)
		_set_state(MotionState.HOVER)
	else:
		velocity.y = maxf(velocity.y - g * delta, -profile.max_fall_speed)
		_set_state(MotionState.AIRBORNE if velocity.y > 0.0 else MotionState.FALLING)


func _update_air_dash(delta: float) -> void:
	air_time += delta
	if _cmd.move.length_squared() > 0.01:
		var steer := deg_to_rad(profile.air_dash_steer_deg) * delta
		var target := _cmd.move.normalized()
		var angle := _dash_dir.signed_angle_to(target, Vector3.UP)
		_dash_dir = _dash_dir.rotated(Vector3.UP, clampf(angle, -steer, steer)).normalized()
	velocity = _dash_dir * profile.air_dash_speed * maxf(_m_speed, 0.5)
	if state_time >= profile.air_dash_duration or _m_block_move:
		var keep_hover := hover_engaged and en > 0.0 and not _m_block_thrust
		_set_state(MotionState.HOVER if keep_hover else MotionState.FALLING)


func _can_dash(cost: float) -> bool:
	return not _m_block_dash and _dash_cooldown <= 0.0 and en >= cost


func _start_dash(in_air: bool) -> void:
	_dash_buffer = 0.0
	_dash_cooldown = profile.dash_cooldown
	var dir := _cmd.move
	if dir.length_squared() < 0.01:
		dir = get_forward()
	dir.y = 0.0
	_dash_dir = dir.normalized()
	if in_air:
		_spend(profile.air_dash_cost * _m_en_cost)
		hover_engaged = true
		velocity = _dash_dir * profile.air_dash_speed
		_set_state(MotionState.AIR_DASH)
	else:
		_spend(profile.ground_dash_cost * _m_en_cost)
		velocity = _dash_dir * profile.ground_dash_speed
		_set_state(MotionState.GROUND_DASH)
	dashed.emit(in_air)


# --------------------------------------------------------------------------
# Post-move: landing, ledges, ceilings, stuck recovery
# --------------------------------------------------------------------------

func _post_move(vy_before: float, delta: float) -> void:
	_record_collisions()
	if is_on_ceiling() and velocity.y > 0.0:
		velocity.y = 0.0

	if is_grounded_state():
		if is_on_floor():
			_coyote = COYOTE_TIME
			_last_safe_position = global_position
		else:
			_coyote -= delta
			if _coyote <= 0.0:
				takeoff_height = global_position.y
				hover_engaged = false
				air_time = 0.0
				_set_state(MotionState.FALLING)
		return

	var can_land := state != MotionState.TAKEOFF or state_time > 0.06
	if can_land and is_on_floor() and vy_before <= 0.5:
		_land(-vy_before)
		return

	# Stuck recovery: resting on a steep edge / wedge without a floor contact.
	if state == MotionState.FALLING and absf(global_position.y - _stuck_ref_y) < 0.03 and (is_on_wall() or is_on_floor()):
		_stuck_timer += delta
		if _stuck_timer >= STUCK_TIME:
			_land(0.0)
	else:
		_stuck_timer = 0.0
		_stuck_ref_y = global_position.y

	if _bounds and global_position.y < _bounds.kill_y:
		push_warning("MechMotor: fell below kill_y, restoring last safe position")
		reset_to(_last_safe_position + Vector3.UP * 0.5)


func _land(impact: float) -> void:
	last_impact_speed = impact
	var hard := impact >= profile.hard_landing_speed
	_landing_timer = profile.hard_landing_recovery if hard else profile.landing_recovery
	hover_engaged = false
	active_descent = false
	air_time = 0.0
	_stuck_timer = 0.0
	velocity.y = 0.0
	# regen delay restarts on touchdown (EN never refills during the fall)
	_regen_timer = profile.regen_delay
	_set_state(MotionState.LANDING)
	landed.emit(impact, hard)


func _enforce_ceiling() -> void:
	if _bounds == null:
		return
	var hard_ceiling := _bounds.ceiling_y - BODY_HEIGHT
	if global_position.y >= hard_ceiling and velocity.y > 0.0:
		velocity.y = 0.0
	if global_position.y > hard_ceiling + 0.5:
		velocity.y = minf(velocity.y, -2.0)


func _enforce_bounds() -> void:
	if _bounds == null:
		return
	var clamped := _bounds.clamp_horizontal(global_position)
	if not clamped.is_equal_approx(global_position):
		global_position = clamped
		velocity = Vector3(0.0, velocity.y, 0.0)


func _record_collisions() -> void:
	last_collisions.clear()
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var col := c.get_collider() as Node
		if col:
			last_collisions.append(col.name)


# --------------------------------------------------------------------------
# Facing, energy, modifiers, helpers
# --------------------------------------------------------------------------

func _update_facing(delta: float) -> void:
	if _m_block_facing:
		return
	var desired := Vector3(_cmd.face_dir.x, 0.0, _cmd.face_dir.z)
	if desired.length_squared() < 0.0001:
		if state == MotionState.GROUND_DASH or state == MotionState.AIR_DASH:
			desired = _dash_dir
		elif _cmd.move.length_squared() > 0.01:
			desired = _cmd.move
		else:
			return
	var target_yaw := atan2(-desired.x, -desired.z)
	rotation.y = rotate_toward(rotation.y, target_yaw, deg_to_rad(profile.turn_speed_deg) * _m_turn * delta)


func _spend(amount: float) -> void:
	if amount <= 0.0:
		return
	var before := en
	en = maxf(en - amount, 0.0)
	_regen_timer = profile.regen_delay
	en_changed.emit(en, profile.max_en)
	if before > 0.0 and en <= 0.0:
		en_exhausted.emit()


func _regen(delta: float) -> void:
	_regen_timer = maxf(_regen_timer - delta, 0.0)
	if _m_block_regen or _regen_timer > 0.0 or en >= profile.max_en:
		return
	var rate := 0.0
	if state == MotionState.GROUNDED or state == MotionState.LANDING:
		rate = profile.ground_regen_per_sec
	elif is_air_state():
		rate = profile.air_regen_per_sec
	if rate > 0.0:
		en = minf(en + rate * delta, profile.max_en)
		en_changed.emit(en, profile.max_en)


## Highest upward speed that can still stop within `room` metres at `brake`.
static func _approach_speed(room: float, brake: float) -> float:
	return sqrt(2.0 * maxf(brake, 1.0) * maxf(room, 0.0))


## Velocity steering: accelerate along the input direction, bleed sideways
## velocity at `grip`, decay overspeed separately. Tunable inertia per profile.
static func _steer(h: Vector3, target: Vector3, accel: float, decel: float, grip: float, overspeed: float, delta: float) -> Vector3:
	var tlen := target.length()
	if tlen < 0.001:
		return h.move_toward(Vector3.ZERO, decel * delta)
	var dir := target / tlen
	var par := h.dot(dir)
	var perp := h - dir * par
	if par <= tlen:
		var rate := accel if par >= 0.0 else accel + decel
		par = move_toward(par, tlen, rate * delta)
	else:
		par = move_toward(par, tlen, overspeed * delta)
	perp = perp.move_toward(Vector3.ZERO, grip * delta)
	return dir * par + perp


func _tick_modifiers(delta: float) -> void:
	var expired: Array[StringName] = []
	for m: MovementModifier in _modifiers.values():
		if m.duration >= 0.0:
			m.duration -= delta
			if m.duration <= 0.0:
				expired.append(m.id)
	if not expired.is_empty():
		for id in expired:
			_modifiers.erase(id)
		_recompute_modifiers()


func _recompute_modifiers() -> void:
	_m_speed = 1.0
	_m_accel = 1.0
	_m_turn = 1.0
	_m_gravity = 1.0
	_m_block_move = false
	_m_block_jump = false
	_m_block_dash = false
	_m_block_thrust = false
	_m_block_facing = false
	_m_forced = false
	_m_en_cost = 1.0
	_m_block_regen = false
	for m: MovementModifier in _modifiers.values():
		_m_speed *= m.speed_mult
		_m_accel *= m.accel_mult
		_m_turn *= m.turn_mult
		_m_gravity *= m.gravity_mult
		_m_block_move = _m_block_move or m.block_move
		_m_block_jump = _m_block_jump or m.block_jump
		_m_block_dash = _m_block_dash or m.block_dash
		_m_block_thrust = _m_block_thrust or m.block_thrust
		_m_block_facing = _m_block_facing or m.block_facing
		_m_en_cost *= m.en_cost_mult
		_m_block_regen = _m_block_regen or m.block_en_regen
		if m.forced:
			_m_forced = true
			_forced_mod = m
	_m_speed = clampf(_m_speed, 0.0, 2.0)
	_m_en_cost = clampf(_m_en_cost, 0.25, 4.0)
	_m_gravity = clampf(_m_gravity, 0.5, 3.0)


func _set_state(new_state: int) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	state_time = 0.0
	if record_transitions:
		transition_log.append(STATE_NAMES[new_state])
	motion_state_changed.emit(old, new_state)
