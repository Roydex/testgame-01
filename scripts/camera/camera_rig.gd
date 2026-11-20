class_name CameraRig
extends Node3D
## Unified third-person camera: free orbit, lock-on framing, smoothed
## ground/air follow, height-difference tracking, dash FOV, occlusion pull-in.
## Automatic rotation is rate-limited so it never yanks the view.

@export_group("Follow")
@export var focus_height: float = 3.2
## Arm length presets (near / mid / far), cycled with the camera_zoom action.
@export var distance_presets: PackedFloat32Array = PackedFloat32Array([7.5, 10.0, 13.0])
@export var distance_preset_index: int = 1
## How fast the arm length eases to a newly selected preset (1/s).
@export var distance_change_sharpness: float = 5.0
## Current base arm length (eases toward the selected preset).
var distance: float = 10.0
@export var shoulder_offset: float = 1.2
## Exponential follow sharpness (1/s). Vertical is softer so take-off and
## landing do not jolt the view.
@export var follow_sharpness_h: float = 22.0
@export var follow_sharpness_v: float = 7.0
## Extra distance at full dash speed.
@export var speed_pullback: float = 1.2

@export_group("Free Look")
@export var mouse_sensitivity: float = 0.0025
@export var pitch_min_deg: float = -70.0
@export var pitch_max_deg: float = 55.0

@export_group("Lock-On")
@export var lock_sharpness: float = 5.0
## Max automatic rotation speed while locked (deg/s).
@export var lock_max_turn_deg: float = 200.0
@export var lock_pitch_factor: float = 0.6
@export var lock_pitch_min_deg: float = -50.0
@export var lock_pitch_max_deg: float = 42.0
## 0 = look at player, 1 = look at target (angular blend).
@export var lock_aim_weight: float = 0.45
## The player's chest is kept within this angle of the view centre while locked.
@export var lock_player_max_angle_deg: float = 26.0
## Extra arm length per metre of height difference.
@export var lock_height_distance_factor: float = 0.18
@export var lock_max_extra_distance: float = 5.0
## Orbit pitch used for the camera POSITION while locked. Looking up at a high
## target tilts the view (look-at) instead of dropping the camera to the floor.
@export var lock_orbit_pitch_min_deg: float = -35.0
@export var lock_orbit_pitch_max_deg: float = 8.0
## Close-range lock framing: under this horizontal distance the camera
## swings out to the shoulder and rises so the target is not hidden behind
## the player's own mech.
@export var lock_close_distance: float = 8.0
@export var lock_close_shoulder: float = 3.2
@export var lock_close_height: float = 1.8
@export var lock_manual_yaw_deg: float = 25.0
@export var lock_manual_pitch_deg: float = 15.0
@export var lock_offset_return_delay: float = 0.8
@export var lock_offset_return_speed: float = 2.5

@export_group("Experiments (playtest round 2)")
## 动态对决镜头: under this horizontal lock distance the view swings to a
## three-quarter side framing of both mechs (side kept while it lasts).
@export var duel_range: float = 14.0
@export var duel_side_deg: float = 55.0
@export var duel_aim_weight: float = 0.5
@export var duel_extra_dist_per_m: float = 0.35
## Close-up on a cinematic moment (parry, riposte, finisher): arm length ×.
@export var cine_zoom: float = 0.6
## 自由瞄准: lock framing keeps the target near the crosshair, and the mouse
## gets a wider offset range for leading shots.
@export var free_aim_lock_weight: float = 0.85
@export var free_aim_manual_yaw_deg: float = 35.0
@export var free_aim_manual_pitch_deg: float = 20.0

@export_group("Placement aim (orbital marking)")
## While the player marks a ground point the camera rises and looks down;
## the mouse turns it freely even when a target is locked.
@export var placement_height: float = 9.0
@export var placement_distance: float = 13.0
@export var placement_pitch_min_deg: float = -80.0
@export var placement_pitch_max_deg: float = -8.0
@export var placement_sharpness: float = 6.0

@export_group("FOV")
@export var base_fov: float = 70.0
@export var dash_fov: float = 78.0
@export var fov_sharpness: float = 6.0

@export_group("Occlusion")
@export var collision_radius: float = 0.35
@export_flags_3d_physics var collision_mask: int = 1
@export var occlusion_return_sharpness: float = 4.0
## Below this arm length the rig tries a raised camera position instead.
@export var min_comfort_distance: float = 2.8
@export var raise_height: float = 4.0
## Mech visual fades out between these arm lengths (camera too close).
@export var fade_start_distance: float = 3.0
@export var fade_end_distance: float = 1.2
## How fast the arm swings to an alternative (unoccluded) position (1/s).
@export var arm_swing_sharpness: float = 6.0

var mech: MechMotor
var targeting: TargetingSystem
var camera: Camera3D
var yaw: float = 0.0
var pitch: float = deg_to_rad(-12.0)
var occluded: bool = false
var lock_blend: float = 0.0
## Allow tests / autopilot to drive the free camera without a mouse.
var mouse_enabled: bool = true

var _focus: Vector3
var _cam_dist: float
var _yaw_offset := 0.0
var _pitch_offset := 0.0
var _offset_idle := 0.0
var _aim_dir := Vector3.ZERO
var _arm_dir := Vector3.ZERO
var _close_blend := 0.0
var _prev_q := Quaternion.IDENTITY
var _has_prev_q := false
var _initialized := false
## Camera shake "trauma" (0..1); shake = trauma², decays quickly.
var shake_trauma: float = 0.0
@export_group("Shake")
@export var shake_max_angle_deg: float = 2.6
@export var shake_max_offset: float = 0.12
@export var shake_decay: float = 3.0
## FOV punch spring (deg, decays with fov_sharpness).
var _fov_punch := 0.0
var _duel_blend := 0.0
var _duel_side := 1.0
var _cine_left := 0.0
var _cine_total := 0.4
## Set by the player brain while the mech is in the AIM (placement) state.
var placement_mode := false
var _place_blend := 0.0


func _ready() -> void:
	top_level = true
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = base_fov
	camera.near = 0.1
	camera.far = 1500.0
	add_child(camera)
	camera.current = true
	process_physics_priority = 10


func setup(p_mech: MechMotor, p_targeting: TargetingSystem) -> void:
	mech = p_mech
	targeting = p_targeting
	yaw = mech.rotation.y
	snap()


func snap() -> void:
	distance = get_target_distance()
	_focus = mech.global_position + Vector3.UP * focus_height
	_cam_dist = distance
	_initialized = true
	_update_camera(0.0, true)


## Horizontal basis used by brains to map input to world space.
func add_shake(amount: float) -> void:
	shake_trauma = clampf(shake_trauma + amount, 0.0, 1.0)


## Brief zoom-in on heavy impacts (deg).
func add_fov_punch(deg: float) -> void:
	_fov_punch = maxf(_fov_punch, deg)


## Short close-up (arm pulled in) for a cinematic moment.
func cinematic(duration: float = 0.4) -> void:
	_cine_total = maxf(duration, 0.05)
	_cine_left = _cine_total


## Enter / leave the raised placement view. On entry the view turns to the
## locked target (if any) so the marker starts on it.
func set_placement_mode(on: bool) -> void:
	if on == placement_mode:
		return
	placement_mode = on
	if on and targeting and targeting.has_target() and mech:
		var to := targeting.current.global_position - mech.global_position  # its feet: the marker sits on the ground
		var horiz := Vector2(to.x, to.z).length()
		yaw = atan2(-to.x, -to.z)
		# the view ray always passes through the (raised) focus point, so aim
		# from there: the marker starts right on the locked target
		var cam_h := focus_height + placement_height - to.y
		pitch = clampf(-atan2(cam_h, maxf(horiz, 0.5)), deg_to_rad(placement_pitch_min_deg), deg_to_rad(placement_pitch_max_deg))
	elif on:
		pitch = clampf(pitch - deg_to_rad(25.0), deg_to_rad(placement_pitch_min_deg), deg_to_rad(placement_pitch_max_deg))


## 0..1: how far the duel (three-quarter side) framing is blended in.
func duel_blend() -> float:
	return _duel_blend


func get_yaw_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


func is_locked() -> bool:
	return targeting != null and targeting.has_target()


func get_target_distance() -> float:
	if distance_presets.is_empty():
		return distance
	return distance_presets[clampi(distance_preset_index, 0, distance_presets.size() - 1)]


## Selects the next distance preset (wraps around). Returns the new target length.
func cycle_distance() -> float:
	if not distance_presets.is_empty():
		distance_preset_index = (distance_preset_index + 1) % distance_presets.size()
	return get_target_distance()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"camera_zoom"):
		cycle_distance()
		return
	if not mouse_enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		add_look_input((event as InputEventMouseMotion).relative * mouse_sensitivity)


## Look input in radians (x = yaw, y = pitch). In lock mode it becomes a
## bounded offset that eases back.
func add_look_input(delta_rad: Vector2) -> void:
	if placement_mode:
		yaw = wrapf(yaw - delta_rad.x, -PI, PI)
		pitch = clampf(pitch - delta_rad.y, deg_to_rad(placement_pitch_min_deg), deg_to_rad(placement_pitch_max_deg))
	elif is_locked():
		var my := free_aim_manual_yaw_deg if Experiments.free_aim else lock_manual_yaw_deg
		var mp := free_aim_manual_pitch_deg if Experiments.free_aim else lock_manual_pitch_deg
		_yaw_offset = clampf(_yaw_offset - delta_rad.x, -deg_to_rad(my), deg_to_rad(my))
		_pitch_offset = clampf(_pitch_offset - delta_rad.y, -deg_to_rad(mp), deg_to_rad(mp))
		_offset_idle = 0.0
	else:
		yaw = wrapf(yaw - delta_rad.x, -PI, PI)
		pitch = clampf(pitch - delta_rad.y, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))


func _physics_process(delta: float) -> void:
	if mech == null or not _initialized:
		return
	_update_camera(delta, false)


func _update_camera(delta: float, instant: bool) -> void:
	# --- focus follow (separate vertical smoothing for ground/air transitions)
	_place_blend = (1.0 if placement_mode else 0.0) if instant else move_toward(_place_blend, 1.0 if placement_mode else 0.0, delta * placement_sharpness * 0.5)
	var want_focus := mech.global_position + Vector3.UP * (focus_height + placement_height * _ease(_place_blend))
	var kh := 1.0 if instant else 1.0 - exp(-follow_sharpness_h * delta)
	var kv := 1.0 if instant else 1.0 - exp(-follow_sharpness_v * delta)
	_focus.x = lerpf(_focus.x, want_focus.x, kh)
	_focus.z = lerpf(_focus.z, want_focus.z, kh)
	_focus.y = lerpf(_focus.y, want_focus.y, kv)
	# never let the lagging focus sit more than 3 m from the mech
	if _focus.distance_to(want_focus) > 3.0:
		_focus = want_focus + (_focus - want_focus).normalized() * 3.0

	var locked := is_locked() and not placement_mode
	var extra_dist := 0.0
	var close_t := 0.0
	lock_blend = move_toward(lock_blend, 1.0 if locked else 0.0, (1.0 if instant else delta * 3.0))

	if locked:
		var tp := targeting.get_target_point()
		var to := tp - _focus
		var horiz := Vector2(to.x, to.z).length()
		var desired_yaw := yaw - _yaw_offset_applied()
		if horiz > 2.5:
			desired_yaw = atan2(-to.x, -to.z)
		# 动态对决镜头: swing to the side the camera is already on
		var duel_want := 1.0 if Experiments.duel_cam and horiz < duel_range else 0.0
		if duel_want > 0.0 and _duel_blend < 0.01:
			_duel_side = 1.0 if wrapf(yaw - desired_yaw, -PI, PI) >= 0.0 else -1.0
		_duel_blend = duel_want if instant else move_toward(_duel_blend, duel_want, delta * 2.0)
		desired_yaw += _duel_side * deg_to_rad(duel_side_deg) * _duel_blend
		var desired_pitch := clampf(atan2(to.y, maxf(horiz, 0.1)) * lock_pitch_factor,
			deg_to_rad(lock_pitch_min_deg), deg_to_rad(lock_pitch_max_deg))
		_offset_idle += delta
		if _offset_idle > lock_offset_return_delay:
			_yaw_offset = move_toward(_yaw_offset, 0.0, lock_offset_return_speed * delta * absf(_yaw_offset) + 0.2 * delta)
			_pitch_offset = move_toward(_pitch_offset, 0.0, lock_offset_return_speed * delta * absf(_pitch_offset) + 0.2 * delta)
		yaw = _approach_angle(yaw, desired_yaw + _yaw_offset, delta, instant)
		pitch = _approach_angle(pitch, desired_pitch + _pitch_offset, delta, instant)
		pitch = clampf(pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
		close_t = clampf((lock_close_distance - horiz) / lock_close_distance, 0.0, 1.0) * (1.0 - _duel_blend)
		extra_dist = clampf(absf(to.y) * lock_height_distance_factor + maxf(horiz - 40.0, 0.0) * 0.02, 0.0, lock_max_extra_distance)
		extra_dist += _duel_blend * horiz * duel_extra_dist_per_m
	else:
		_yaw_offset = 0.0
		_pitch_offset = 0.0
		_duel_blend = 0.0 if instant else move_toward(_duel_blend, 0.0, delta * 2.0)

	# --- dynamic distance: preset (eased), height difference, speed pull-back
	distance = get_target_distance() if instant else lerpf(distance, get_target_distance(), 1.0 - exp(-distance_change_sharpness * delta))
	var spd := mech.get_horizontal_velocity().length()
	var p := mech.profile
	var speed_t := clampf((spd - p.ground_max_speed) / maxf(p.air_dash_speed - p.ground_max_speed, 1.0), 0.0, 1.0)
	var want_dist := distance + extra_dist + speed_t * speed_pullback
	want_dist = lerpf(want_dist, placement_distance, _ease(_place_blend))
	if _cine_left > 0.0 and not instant:
		_cine_left = maxf(_cine_left - delta, 0.0)
		var ck := clampf(minf(_cine_left, _cine_total - _cine_left) / 0.08, 0.0, 1.0)
		want_dist *= lerpf(1.0, cine_zoom, ck)

	var basis_free := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var orbit_pitch := pitch
	if lock_blend > 0.0:
		var clamped := clampf(pitch, deg_to_rad(lock_orbit_pitch_min_deg), deg_to_rad(lock_orbit_pitch_max_deg))
		orbit_pitch = lerpf(pitch, clamped, lock_blend)
	var basis_orbit := Basis.from_euler(Vector3(orbit_pitch, yaw, 0.0))
	_close_blend = close_t if instant else lerpf(_close_blend, close_t, 1.0 - exp(-4.0 * delta))
	var shoulder := lerpf(shoulder_offset, lock_close_shoulder, _close_blend)
	var desired_cam := _focus + basis_orbit.x * shoulder + basis_orbit.z * want_dist + Vector3.UP * lock_close_height * _close_blend

	# --- occlusion: sphere sweep from the focus to the desired position.
	# If the arm would collapse (backed against a wall), try a raised arm and,
	# while locked (view is look-at driven), arms swung to either side.
	var arm := desired_cam - _focus
	var full_len := arm.length()
	var safe_len := full_len * _sweep(_focus, desired_cam)
	var best_arm := arm
	if safe_len < min_comfort_distance:
		var candidates: Array[Vector3] = [arm + Vector3.UP * raise_height]
		if locked:
			for a in [50.0, -50.0, 90.0, -90.0]:
				candidates.append(arm.rotated(Vector3.UP, deg_to_rad(a)) + Vector3.UP * raise_height * 0.5)
		var best_len := safe_len
		for c in candidates:
			var lc := c.length() * _sweep(_focus, _focus + c)
			if lc > best_len + 0.5:
				best_len = lc
				best_arm = c
	# smooth the arm DIRECTION, then re-sweep along it so the camera can never
	# end up inside geometry while it swings
	var arm_want := best_arm.normalized()
	if instant or _arm_dir == Vector3.ZERO:
		_arm_dir = arm_want
	else:
		_arm_dir = _arm_dir.slerp(arm_want, 1.0 - exp(-arm_swing_sharpness * delta)).normalized()
	var arm_len := best_arm.length()
	var safe := _sweep(_focus, _focus + _arm_dir * arm_len)
	safe_len = arm_len * safe
	occluded = safe < 0.999 or not best_arm.is_equal_approx(arm)
	if instant or safe_len < _cam_dist:
		_cam_dist = safe_len  # pull in immediately
	else:
		_cam_dist = lerpf(_cam_dist, safe_len, 1.0 - exp(-occlusion_return_sharpness * delta))
	var cam_pos := _focus + _arm_dir * _cam_dist
	var vis := mech.get_node_or_null(^"Visual")
	if vis and vis.has_method(&"set_camera_fade"):
		vis.call(&"set_camera_fade", inverse_lerp(fade_end_distance, fade_start_distance, _cam_dist))

	# --- orientation: free basis blended with lock look-at.
	# The lock view direction is an angular blend between "toward the player"
	# and "toward the target", capped so the player always stays in frame.
	var q_free := basis_free.get_rotation_quaternion()
	var q := q_free
	if lock_blend > 0.0 and locked:
		var chest := mech.global_position + Vector3.UP * (focus_height - 0.7)
		var d_p := (chest - cam_pos)
		var d_t := (targeting.get_target_point() - cam_pos)
		if d_p.length() > 0.5 and d_t.length() > 0.5:
			d_p = d_p.normalized()
			d_t = d_t.normalized()
			var sep := d_p.angle_to(d_t)
			var w := free_aim_lock_weight if Experiments.free_aim else lock_aim_weight
			var max_ang := 40.0 if Experiments.free_aim else lock_player_max_angle_deg
			w = lerpf(w, maxf(duel_aim_weight, w - 0.2) if Experiments.free_aim else duel_aim_weight, _duel_blend)
			max_ang = lerpf(max_ang, 45.0, _duel_blend)
			if sep > 0.001:
				w = minf(w, deg_to_rad(max_ang) / sep)
			var want_dir := d_p.slerp(d_t, clampf(w, 0.0, 1.0)).normalized()
			_aim_dir = want_dir if (instant or _aim_dir == Vector3.ZERO) else _aim_dir.slerp(want_dir, 1.0 - exp(-lock_sharpness * 1.5 * delta)).normalized()
			if absf(_aim_dir.dot(Vector3.UP)) < 0.98:
				var q_lock := Basis.looking_at(_aim_dir, Vector3.UP).get_rotation_quaternion()
				q = q_free.slerp(q_lock, lock_blend)
	elif lock_blend > 0.0 and _aim_dir != Vector3.ZERO:
		# lock just released: ease from the last lock view back to the free view
		var q_last := Basis.looking_at(_aim_dir, Vector3.UP).get_rotation_quaternion()
		q = q_free.slerp(q_last, lock_blend)
	if lock_blend <= 0.0:
		_aim_dir = -basis_free.z
	# rate-limit any automatic rotation (lock / switch / release)
	if not instant and lock_blend > 0.0 and _has_prev_q:
		var ang := _prev_q.angle_to(q)
		var max_step := deg_to_rad(lock_max_turn_deg) * delta
		if ang > max_step:
			q = _prev_q.slerp(q, max_step / ang)
	_prev_q = q
	_has_prev_q = true
	global_transform = Transform3D(Basis.IDENTITY, cam_pos)
	var cam_basis := Basis(q)
	if shake_trauma > 0.0 and not instant:
		shake_trauma = maxf(shake_trauma - shake_decay * delta, 0.0)
		var tr := pow(shake_trauma, 1.5)
		var s := tr * deg_to_rad(shake_max_angle_deg)
		var t := Time.get_ticks_msec() * 0.001
		cam_basis = cam_basis * Basis.from_euler(Vector3(sin(t * 47.0) * s, sin(t * 39.0 + 1.3) * s, sin(t * 31.0 + 2.1) * s * 0.5))
		cam_pos += cam_basis * Vector3(sin(t * 53.0), sin(t * 41.0 + 0.7), 0.0) * tr * shake_max_offset
	camera.global_transform = Transform3D(cam_basis, cam_pos)

	# --- FOV
	var dashing := mech.state == MechMotor.MotionState.GROUND_DASH or mech.state == MechMotor.MotionState.AIR_DASH
	var fov_t := 1.0 if dashing else speed_t
	var want_fov := lerpf(base_fov, dash_fov, fov_t)
	camera.fov = want_fov if instant else lerpf(camera.fov, want_fov, 1.0 - exp(-fov_sharpness * delta))
	if _fov_punch > 0.01 and not instant:
		camera.fov -= _fov_punch
		_fov_punch = move_toward(_fov_punch, 0.0, delta * 30.0)


static func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _yaw_offset_applied() -> float:
	return _yaw_offset


func _approach_angle(current: float, target: float, delta: float, instant: bool) -> float:
	if instant:
		return target
	var diff := wrapf(target - current, -PI, PI)
	var step := diff * (1.0 - exp(-lock_sharpness * delta))
	var max_step := deg_to_rad(lock_max_turn_deg) * delta
	step = clampf(step, -max_step, max_step)
	return wrapf(current + step, -PI, PI)


func _sweep(from: Vector3, to: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = collision_radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = to - from
	q.collision_mask = collision_mask
	q.exclude = [mech.get_rid()]
	var res := space.cast_motion(q)
	if res.is_empty():
		return 1.0
	return res[0]
