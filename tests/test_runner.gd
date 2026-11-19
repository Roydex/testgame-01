extends Node
## Automated movement / camera acceptance tests (phase: Ground-Air prototype).
## Run headless with a fixed 60 Hz step:
##   Godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn
## Optional: -- --only=T05   (substring filter on test id)
## Writes tests/logs/test_results.log and exits with 0 (all pass) or 1.

const DT := 1.0 / 60.0
const PROFILE_NAMES := ["base", "seraph", "hellfang", "ark", "oracle"]

var results: Array[Dictionary] = []
var log_lines: PackedStringArray = []
var arena: Node3D
var _filter := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_filter = a.substr(7)
	_run_all.call_deferred()


func _log(s: String) -> void:
	print(s)
	log_lines.append(s)


func _run_all() -> void:
	_log("=== Ground-Air Hybrid movement tests  %s  Godot %s ===" % [Time.get_datetime_string_from_system(), Engine.get_version_info().string])
	_log("physics %d Hz, physics engine: %s" % [Engine.physics_ticks_per_second, ProjectSettings.get_setting("physics/3d/physics_engine")])
	var tests := [
		["T01", "M01 ground move / accel / decel / turn", t01_ground_move],
		["T02", "M02 air steering + per-mech inertia", t02_air_inertia],
		["T03", "State chain: dash>takeoff>ascend>hover>air dash>fall>land", t03_state_chain],
		["T04", "M05 dashes compress remaining air time", t04_energy_compression],
		["T05", "EN exhaustion -> normal descent, no stall, regen", t05_en_exhaustion],
		["T06", "Ascent ceiling (takeoff+10 m) and map ceiling", t06_ceilings],
		["T07", "M10 no tunnelling: walls / slabs / corridor", t07_collisions],
		["T08", "M10 seeded fuzz: bounds, penetration, airtime, stalls", t08_fuzz],
		["T09", "Combat layer via modifiers only; no infinite hover", t09_combat_layer],
		["T10", "M06 lock camera framing & rotation limits", t10_camera_lock],
		["T11", "Targeting: switch / destroyed / out of range / occluded", t11_targeting],
		["T12", "M03 support: movement-only pursuit of hovering target", t12_pursuit_support],
		["T13", "M04 support: evading test-fixture shots in the air", t13_air_evasion],
	]
	for t in tests:
		if _filter != "" and not (t[0] as String).contains(_filter):
			continue
		_log("\n--- %s  %s" % [t[0], t[1]])
		var res: Dictionary = {"id": t[0], "name": t[1], "pass": true, "notes": PackedStringArray()}
		await _new_arena()
		await (t[2] as Callable).call(res)
		await _free_arena()
		results.append(res)
		_log("%s  %s" % ["PASS" if res.pass else "FAIL", t[0]])
	var failed := 0
	_log("\n=== SUMMARY ===")
	for r in results:
		_log("%-4s %-5s %s" % [r.id, "PASS" if r.pass else "FAIL", r.name])
		if not r.pass:
			failed += 1
	_log("%d/%d passed" % [results.size() - failed, results.size()])
	var f := FileAccess.open(ProjectSettings.globalize_path("res://tests/logs/test_results.log"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines) + "\n")
		f.close()
	get_tree().quit(1 if failed > 0 else 0)


# ------------------------------------------------------------------ helpers

func _new_arena(with_targets := false) -> void:
	arena = Node3D.new()
	arena.name = "Arena"
	add_child(arena)
	GrayboxBuilder.build(arena, with_targets)
	await get_tree().physics_frame


func _free_arena() -> void:
	if arena:
		arena.queue_free()
		arena = null
	await get_tree().physics_frame
	await get_tree().physics_frame


func _rebuild_arena(with_targets: bool) -> void:
	await _free_arena()
	await _new_arena(with_targets)


func _spawn(profile_idx: int, pos: Vector3, settle := true) -> MechMotor:
	var m := MechFactory.create_mech(MechFactory.load_profile(profile_idx), 0, Color.GRAY, false)
	m.position = pos
	m.record_transitions = true
	arena.add_child(m)
	if settle:
		await _ticks(30)
	return m


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Runs `seconds` of simulation. `drive.call(m, t)` sets the command before
## each tick; `probe.call(m, t)` observes after it (optional).
func _sim(m: MechMotor, seconds: float, drive: Callable, probe := Callable(), until := Callable()) -> float:
	var t := 0.0
	while t < seconds:
		drive.call(m, t)
		await get_tree().physics_frame
		t += DT
		if probe.is_valid():
			probe.call(m, t)
		if until.is_valid() and until.call(m, t):
			break
	return t


func _clear(m: MechMotor) -> void:
	m.command.move = Vector3.ZERO
	m.command.ascend = false
	m.command.descend = false
	m.command.face_dir = Vector3.ZERO


func _check(res: Dictionary, cond: bool, msg: String) -> void:
	res.notes.append(("  ok   " if cond else "  FAIL ") + msg)
	_log(("  ok   " if cond else "  FAIL ") + msg)
	if not cond:
		res.pass = false


func _info(msg: String) -> void:
	_log("  info " + msg)


## Brings a mech into a steady hover at ~6 m above its takeoff point.
func _enter_hover(m: MechMotor) -> void:
	m.command.jump_pressed = true
	await _sim(m, 0.8, func(mm, _t): mm.command.ascend = true)
	await _sim(m, 0.6, func(mm, _t): mm.command.ascend = false)


func _in_order(log: Array[String], seq: Array) -> bool:
	var i := 0
	for s in log:
		if i < seq.size() and s == seq[i]:
			i += 1
	return i == seq.size()




# ------------------------------------------------------------------ tests
# NOTE: GDScript lambdas capture locals by value, so all state mutated in a
# probe lives in a Dictionary `s`.

func t01_ground_move(res: Dictionary) -> void:
	for idx in MechFactory.PROFILES.size():
		var m := await _spawn(idx, GrayboxBuilder.POINTS.spawn)
		var p := m.profile
		var n: String = PROFILE_NAMES[idx]
		var vmax := p.ground_max_speed
		var s := {"t95": -1.0, "turn": -1.0, "yaw": -1.0, "stop": -1.0}
		var fwd := func(mm: MechMotor, _t: float) -> void:
			mm.command.move = Vector3(0, 0, -1)
		var probe_acc := func(mm: MechMotor, t: float) -> void:
			if s.t95 < 0.0 and mm.get_horizontal_velocity().length() >= vmax * 0.95:
				s.t95 = t
		await _sim(m, 2.0, fwd, probe_acc)
		var v_end := m.get_horizontal_velocity().length()
		var exp_acc := vmax / p.ground_accel
		_check(res, s.t95 > 0.0 and s.t95 <= exp_acc * 1.3 + 0.1, "[%s] accel to 95%% max in %.2fs (expected ~%.2fs)" % [n, s.t95, exp_acc])
		_check(res, absf(v_end - vmax) < vmax * 0.02, "[%s] top speed %.2f / %.2f m/s" % [n, v_end, vmax])
		var target_yaw := atan2(-1.0, 0.0)
		var right := func(mm: MechMotor, _t: float) -> void:
			mm.command.move = Vector3(1, 0, 0)
		var probe_turn := func(mm: MechMotor, t: float) -> void:
			var hv := mm.get_horizontal_velocity()
			if s.turn < 0.0 and hv.length() > 0.5 and rad_to_deg(hv.angle_to(Vector3.RIGHT)) < 10.0:
				s.turn = t
			if s.yaw < 0.0 and absf(rad_to_deg(angle_difference(mm.rotation.y, target_yaw))) < 5.0:
				s.yaw = t
		await _sim(m, 1.5, right, probe_turn)
		var exp_yaw := 90.0 / p.turn_speed_deg
		_check(res, s.turn > 0.0 and s.turn < 1.0, "[%s] velocity turned 90° in %.2fs" % [n, s.turn])
		_check(res, s.yaw > 0.0 and s.yaw <= exp_yaw * 1.5 + 0.1, "[%s] body yaw turned 90° in %.2fs (expected ~%.2fs)" % [n, s.yaw, exp_yaw])
		var none := func(mm: MechMotor, _t: float) -> void:
			mm.command.move = Vector3.ZERO
		var probe_stop := func(mm: MechMotor, t: float) -> void:
			if s.stop < 0.0 and mm.get_horizontal_velocity().length() < 0.3:
				s.stop = t
		await _sim(m, 1.5, none, probe_stop)
		var exp_stop := vmax / p.ground_decel
		_check(res, s.stop > 0.0 and s.stop <= exp_stop * 1.3 + 0.1, "[%s] decel to stop in %.2fs (expected ~%.2fs)" % [n, s.stop, exp_stop])
		_check(res, m.state == MechMotor.MotionState.GROUNDED and m.is_on_floor(), "[%s] remained GROUNDED on floor" % n)
		m.queue_free()
		await _ticks(2)


func t02_air_inertia(res: Dictionary) -> void:
	var reversal := {}
	for idx in MechFactory.PROFILES.size():
		var n: String = PROFILE_NAMES[idx]
		var m := await _spawn(idx, GrayboxBuilder.POINTS.spawn)
		await _enter_hover(m)
		m.en = m.profile.max_en
		var vmax := m.profile.air_max_speed
		var s := {"rev": -1.0, "r90": -1.0, "lat": -1.0}
		var go := func(dir: Vector3) -> Callable:
			return func(mm: MechMotor, _t: float) -> void:
				mm.command.move = dir
		await _sim(m, 1.2, go.call(Vector3(0, 0, -1)))
		var v0 := m.get_horizontal_velocity().length()
		var probe_rev := func(mm: MechMotor, t: float) -> void:
			var hv := mm.get_horizontal_velocity()
			if s.rev < 0.0 and hv.z > 0.0:
				s.rev = t
			if s.r90 < 0.0 and hv.z >= vmax * 0.9:
				s.r90 = t
		await _sim(m, 2.5, go.call(Vector3(0, 0, 1)), probe_rev)
		var air_ok := m.is_air_state()
		reversal[idx] = s.rev
		_info("[%s] air speed %.1f, reverse-cross %.2fs, 90%% reverse speed %.2fs, state %s" % [n, v0, s.rev, s.r90, m.get_state_name()])
		_check(res, air_ok and s.rev > 0.0 and s.rev < 2.0, "[%s] responds to reverse input in the air (%.2fs < 2.0s)" % [n, s.rev])
		m.en = m.profile.max_en
		await _sim(m, 1.0, go.call(Vector3(0, 0, 1)))
		var probe_lat := func(mm: MechMotor, t: float) -> void:
			var hv := mm.get_horizontal_velocity()
			if s.lat < 0.0 and hv.length() > 1.0 and rad_to_deg(hv.angle_to(Vector3.RIGHT)) < 15.0:
				s.lat = t
		await _sim(m, 2.0, go.call(Vector3(1, 0, 0)), probe_lat)
		_check(res, s.lat > 0.0 and s.lat < 2.0 and m.is_air_state(), "[%s] 90° air turn to within 15° in %.2fs" % [n, s.lat])
		m.queue_free()
		await _ticks(2)
	var se: float = reversal[1]
	var hf: float = reversal[2]
	_check(res, se > 0.0 and hf > 0.0 and se <= hf * 0.7, "inertia differs: seraph reverse %.2fs vs hellfang %.2fs (≥30%% faster)" % [se, hf])
	var distinct := {}
	for k in reversal:
		distinct[snappedf(reversal[k], 0.02)] = true
	_check(res, distinct.size() >= 4, "%d distinct reversal times across 5 profiles" % distinct.size())


func t03_state_chain(res: Dictionary) -> void:
	for idx in MechFactory.PROFILES.size():
		var n: String = PROFILE_NAMES[idx]
		var m := await _spawn(idx, GrayboxBuilder.POINTS.spawn)
		m.transition_log.clear()
		var fwd_d := func(mm: MechMotor, _t: float) -> void:
			mm.command.move = Vector3(0, 0, -1)
		var climb := func(mm: MechMotor, _t: float) -> void:
			mm.command.move = Vector3(0, 0, -1)
			mm.command.ascend = true
		var release := func(mm: MechMotor, _t: float) -> void:
			mm.command.ascend = false
		var side := func(mm: MechMotor, _t: float) -> void:
			mm.command.move = Vector3(1, 0, 0)
		var down := func(mm: MechMotor, _t: float) -> void:
			mm.command.move = Vector3.ZERO
			mm.command.descend = true
		var idle := func(_mm: MechMotor, _t: float) -> void:
			pass
		await _sim(m, 0.3, fwd_d)
		m.command.dash_pressed = true
		await _sim(m, 0.2, fwd_d)
		m.command.jump_pressed = true
		await _sim(m, 1.0, climb)
		await _sim(m, 0.4, release)
		m.command.dash_pressed = true
		await _sim(m, 0.5, side)
		await _sim(m, 4.0, down)
		_clear(m)
		await _sim(m, 0.6, idle)
		var seq := ["GROUND_DASH", "TAKEOFF", "AIRBORNE", "HOVER", "AIR_DASH", "FALLING", "LANDING", "GROUNDED"]
		_info("[%s] %s" % [n, " > ".join(m.transition_log)])
		_check(res, _in_order(m.transition_log, seq), "[%s] visited all 8 states in order" % n)
		_check(res, m.state == MechMotor.MotionState.GROUNDED, "[%s] final state GROUNDED (%s)" % [n, m.get_state_name()])
		m.queue_free()
		await _ticks(2)


func _measure_air_endurance(idx: int, dashes: int, ground_dashes: int) -> Dictionary:
	var m := await _spawn(idx, GrayboxBuilder.POINTS.spawn)
	var fwd_d := func(mm: MechMotor, _t: float) -> void:
		mm.command.move = Vector3(0, 0, -1)
	for i in ground_dashes:
		m.command.dash_pressed = true
		await _sim(m, m.profile.ground_dash_duration + m.profile.dash_cooldown + 0.05, fwd_d)
	_clear(m)
	var en_at_takeoff := m.en
	m.command.jump_pressed = true
	var up := func(mm: MechMotor, _t: float) -> void:
		mm.command.ascend = true
	await _sim(m, 0.45, up)
	var dash_done := 0
	var wait := 0.0
	var t := 0.0
	while t < 15.0:
		_clear(m)
		wait -= DT
		if dash_done < dashes and wait <= 0.0:
			m.command.dash_pressed = true
			m.command.move = Vector3(1 if dash_done % 2 == 0 else -1, 0, 0)
			dash_done += 1
			wait = m.profile.air_dash_duration + m.profile.dash_cooldown + 0.05
		await get_tree().physics_frame
		t += DT
		if (m.state == MechMotor.MotionState.FALLING and m.en <= 0.0) or m.is_grounded_state():
			break
	var out := {"en_takeoff": en_at_takeoff, "sustained": m.air_time, "dashes": dash_done}
	m.queue_free()
	await _ticks(2)
	return out


func t04_energy_compression(res: Dictionary) -> void:
	## Metric: powered air time REMAINING after a chain of k air dashes,
	## compared with the same moment of an identical flight without dashes.
	for idx in MechFactory.PROFILES.size():
		var n: String = PROFILE_NAMES[idx]
		var r0 := await _measure_air_endurance(idx, 0, 0)
		var r1 := await _measure_air_endurance(idx, 1, 0)
		var r2 := await _measure_air_endurance(idx, 2, 0)
		var rg := await _measure_air_endurance(idx, 0, 2)
		var p := MechFactory.load_profile(idx)
		var step := p.air_dash_duration + p.dash_cooldown + 0.05
		var rem0_1: float = r0.sustained - step
		var rem0_2: float = r0.sustained - 2.0 * step
		var rem1: float = r1.sustained - step
		var rem2: float = r2.sustained - 2.0 * step
		_info("[%s] total powered air time: 0 dash %.2fs | 1 air dash %.2fs | 2 air dashes %.2fs | 2 ground dashes first %.2fs (EN at takeoff %.0f)" % [n, r0.sustained, r1.sustained, r2.sustained, rg.sustained, rg.en_takeoff])
		_info("[%s] remaining hover after chain: 1 dash %.2fs vs %.2fs (%.0f%%) | 2 dashes %.2fs vs %.2fs (%.0f%%)" % [n, rem1, rem0_1, 100.0 * rem1 / rem0_1, rem2, rem0_2, 100.0 * rem2 / rem0_2])
		_check(res, rem1 <= rem0_1 * 0.8, "[%s] 1 air dash leaves ≤80%% of remaining hover (%.0f%%)" % [n, 100.0 * rem1 / rem0_1])
		_check(res, rem2 <= rem0_2 * 0.6, "[%s] 2 consecutive air dashes remove ≥40%% of remaining hover (%.0f%% left)" % [n, 100.0 * rem2 / rem0_2])
		_check(res, r2.sustained < r1.sustained and r1.sustained < r0.sustained, "[%s] total air time strictly decreasing with dash count" % n)
		_check(res, rg.sustained <= r0.sustained * 0.8, "[%s] 2 ground dashes before takeoff cut air time to %.0f%%" % [n, 100.0 * rg.sustained / r0.sustained])


func t05_en_exhaustion(res: Dictionary) -> void:
	for idx in MechFactory.PROFILES.size():
		var m := await _spawn(idx, GrayboxBuilder.POINTS.spawn)
		var n: String = PROFILE_NAMES[idx]
		var s := {"ex": -1.0, "rethrust": false, "land": -1.0, "max_air": 0.0}
		m.command.jump_pressed = true
		var bound := m.profile.get_max_air_time_estimate()
		var hold := func(mm: MechMotor, _t: float) -> void:
			mm.command.ascend = true
			mm.command.move = Vector3(0.3, 0, -0.3)
		var probe := func(mm: MechMotor, t: float) -> void:
			if s.ex < 0.0 and mm.en <= 0.0:
				s.ex = t
			if s.ex > 0.0 and s.land < 0.0:
				if mm.velocity.y > 0.5 and mm.is_air_state():
					s.rethrust = true
				if mm.is_grounded_state():
					s.land = t
		var landed_cb := func(_mm: MechMotor, _t: float) -> bool:
			return s.land > 0.0
		await _sim(m, bound + 3.0, hold, probe, landed_cb)
		_info("[%s] EN 0 at %.2fs, landed at %.2fs (bound %.2fs), state %s" % [n, s.ex, s.land, bound, m.get_state_name()])
		_check(res, s.ex > 0.0, "[%s] EN reaches 0 while holding ascend" % n)
		_check(res, not s.rethrust, "[%s] no upward thrust after EN exhaustion" % n)
		_check(res, s.land > 0.0 and s.land <= bound, "[%s] lands within air-time bound (%.2fs ≤ %.2fs)" % [n, s.land, bound])
		_clear(m)
		var idle := func(_mm: MechMotor, _t: float) -> void:
			pass
		await _sim(m, 0.5, idle)
		var en_early := m.en
		await _sim(m, 1.0, idle)
		var en_late := m.en
		_check(res, en_early < 1.0 and en_late > 5.0, "[%s] regen after delay: %.1f @0.5s → %.1f @1.5s after landing" % [n, en_early, en_late])
		m.command.jump_pressed = true
		await _sim(m, 0.3, idle)
		_check(res, m.is_air_state(), "[%s] can jump again after landing (%s)" % [n, m.get_state_name()])
		m.queue_free()
		await _ticks(2)


func _max_height_run(m: MechMotor, seconds: float) -> float:
	var s := {"max": -INF}
	m.command.jump_pressed = true
	var up := func(mm: MechMotor, _t: float) -> void:
		mm.command.ascend = true
	var probe := func(mm: MechMotor, _t: float) -> void:
		s.max = maxf(s.max, mm.global_position.y)
	await _sim(m, seconds, up, probe)
	return s.max


func t06_ceilings(res: Dictionary) -> void:
	var m := await _spawn(0, GrayboxBuilder.POINTS.spawn)
	var start_y := m.global_position.y
	var max_y := await _max_height_run(m, 3.0)
	_check(res, max_y <= start_y + 10.3 and max_y >= start_y + 9.5, "from ground (feet %.2f): max feet %.2f m (limit takeoff+10)" % [start_y, max_y])
	m.queue_free()
	await _ticks(2)
	m = await _spawn(0, GrayboxBuilder.POINTS.tower_a_top + Vector3.UP * 0.3)
	start_y = m.global_position.y
	max_y = await _max_height_run(m, 3.0)
	_check(res, max_y <= start_y + 10.3 and max_y >= start_y + 9.5, "from tower top (feet %.2f): max %.2f (limit %.2f)" % [start_y, max_y, start_y + 10.0])
	m.queue_free()
	await _ticks(2)
	var plat := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(10, 1, 10)
	cs.shape = bs
	plat.add_child(cs)
	plat.position = Vector3(60, 29.5, 60)
	arena.add_child(plat)
	m = await _spawn(0, Vector3(60, 30.2, 60))
	max_y = await _max_height_run(m, 4.0)
	var limit := GrayboxBuilder.CEILING_Y - MechMotor.BODY_HEIGHT
	_check(res, max_y <= limit + 0.3, "map ceiling from 30 m platform: head max %.2f m ≤ %.1f (would be %.1f without map limit)" % [max_y + MechMotor.BODY_HEIGHT, GrayboxBuilder.CEILING_Y, 30.0 + 10.0 + MechMotor.BODY_HEIGHT])
	m.queue_free()
	await _ticks(2)


func t07_collisions(res: Dictionary) -> void:
	var walls := {"thin": -55.0, "thick": -40.0}
	for wname: String in walls:
		var wz: float = walls[wname]
		var start := Vector3(0, 0.2, -47.0) if wname == "thin" else Vector3(0, 0.2, -22.0)
		for idx in [1, 2]:
			for angle in [0.0, 25.0, -40.0]:
				for air in [false, true]:
					var m := await _spawn(idx, start)
					if air:
						await _enter_hover(m)
					var dir := Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(angle))
					var s := {"crossed": false, "min_z": 999.0, "prev": start, "around": false}
					var drive := func(mm: MechMotor, _t: float) -> void:
						mm.command.move = dir
					var probe := func(mm: MechMotor, _t: float) -> void:
						var p: Vector3 = mm.global_position
						var pv: Vector3 = s.prev
						if absf(p.x) < 20.0 + 0.9 and absf(p.x) < 20.0 + 0.9 and p.y < 12.0:
							s.min_z = minf(s.min_z, p.z)
						if pv.z >= wz and p.z < wz:
							if absf(p.x) < 20.0 + 0.9 and p.y + 0.0 < 12.0:
								s.crossed = true
							else:
								s.around = true
						s.prev = p
					for k in 4:
						m.en = m.profile.max_en
						m.command.dash_pressed = true
						await _sim(m, 0.6, drive, probe)
					_check(res, not s.crossed, "[%s wall, %s, %s, %+.0f°] no tunnelling (closest centre z within wall span %.2f, wall plane %.2f%s)" % [wname, PROFILE_NAMES[idx], "air dash" if air else "ground dash", angle, s.min_z, wz, ", slid around wall end" if s.around else ""])
					m.queue_free()
					await _ticks(2)
	for idx in [0, 2, 3]:
		var m := await _spawn(idx, Vector3(-40, 34.0, -50), false)
		m.takeoff_height = 34.0
		var s := {"min_y": 999.0, "max_v": 0.0}
		var down := func(mm: MechMotor, _t: float) -> void:
			mm.command.descend = true
		var probe := func(mm: MechMotor, _t: float) -> void:
			s.min_y = minf(s.min_y, mm.global_position.y)
			s.max_v = maxf(s.max_v, -mm.velocity.y)
		await _sim(m, 4.0, down, probe)
		_check(res, s.min_y >= 16.3 - 0.05, "[%s] fall at up to %.1f m/s onto 0.3 m slab: lowest feet %.2f (slab top 16.30)" % [PROFILE_NAMES[idx], s.max_v, s.min_y])
		_check(res, m.is_grounded_state(), "[%s] landed on slab (%s)" % [PROFILE_NAMES[idx], m.get_state_name()])
		_check(res, s.max_v <= m.profile.descend_speed + 0.1, "[%s] controlled descent capped at %.1f m/s (max %.1f)" % [PROFILE_NAMES[idx], m.profile.descend_speed, s.max_v])
		m.queue_free()
		await _ticks(2)
	# free fall with zero EN from the map ceiling onto the thin slab (terminal velocity)
	var mf := await _spawn(2, Vector3(-40, 35.5, -50), false)
	mf.takeoff_height = 35.5
	mf.en = 0.0
	var sf := {"min_y": 999.0, "max_v": 0.0}
	var idle := func(_mm: MechMotor, _t: float) -> void:
		pass
	var probe_f := func(mm: MechMotor, _t: float) -> void:
		sf.min_y = minf(sf.min_y, mm.global_position.y)
		sf.max_v = maxf(sf.max_v, -mm.velocity.y)
	await _sim(mf, 4.0, idle, probe_f)
	_check(res, sf.min_y >= 16.3 - 0.05, "[hellfang] EN-0 free fall at %.1f m/s onto 0.3 m slab: lowest feet %.2f" % [sf.max_v, sf.min_y])
	mf.queue_free()
	await _ticks(2)
	var m2 := await _spawn(2, GrayboxBuilder.POINTS.slab_under)
	var s2 := {"head": 0.0}
	m2.command.jump_pressed = true
	var climb := func(mm: MechMotor, _t: float) -> void:
		mm.command.ascend = true
		mm.command.move = Vector3(0.3, 0, 0.2) if mm.global_position.x < -36.0 else Vector3.ZERO
	var probe2 := func(mm: MechMotor, _t: float) -> void:
		s2.head = maxf(s2.head, mm.global_position.y + MechMotor.BODY_HEIGHT)
	await _sim(m2, 3.0, climb, probe2)
	_check(res, s2.head <= 8.0 + 0.05, "thrust under 0.4 m slab: head max %.2f (underside 8.00)" % s2.head)
	m2.queue_free()
	await _ticks(2)
	var m3 := await _spawn(1, Vector3(-40, 0.2, 64))
	var s3 := {"dev": 0.0, "head": 0.0, "k": 0}
	var through := func(mm: MechMotor, _t: float) -> void:
		mm.command.move = Vector3(0.15, 0, -1).normalized()
		mm.command.ascend = s3.k == 1
	var probe3 := func(mm: MechMotor, _t: float) -> void:
		if mm.global_position.z < 60 and mm.global_position.z > 44:
			s3.dev = maxf(s3.dev, absf(mm.global_position.x + 40.0))
			s3.head = maxf(s3.head, mm.global_position.y + MechMotor.BODY_HEIGHT)
	for k in 3:
		s3.k = k
		m3.command.dash_pressed = true
		await _sim(m3, 0.5, through, probe3)
	s3.k = 0
	await _sim(m3, 2.0, through, probe3)
	_check(res, s3.dev <= 1.6 - 0.9 + 0.05, "corridor: max lateral offset %.2f m (free space ±0.70)" % s3.dev)
	_check(res, s3.head <= 6.0 + 0.05, "corridor: head stayed under roof (max %.2f ≤ 6.00)" % s3.head)
	_check(res, m3.global_position.z < 44.0, "corridor: passed through (z %.1f < 44)" % m3.global_position.z)
	m3.queue_free()
	await _ticks(2)


func t08_fuzz(res: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261119
	_info("seed %d, 10 runs x 60 s (5 profiles in the open, then 5 runs next to slabs / walls / corridor / towers / steps)" % rng.seed)
	var space := get_viewport().world_3d.direct_space_state
	var probe_shape := CapsuleShape3D.new()
	probe_shape.radius = 0.75
	probe_shape.height = MechMotor.BODY_HEIGHT - 0.4
	var sites := [["open", Vector3.ZERO], ["slab", GrayboxBuilder.POINTS.slab_under], ["walls", Vector3(0, 0.2, -47)],
		["corridor", GrayboxBuilder.POINTS.corridor_in], ["towers", Vector3(48, 0.2, -18)], ["steps", GrayboxBuilder.POINTS.steps_base]]
	for run in MechFactory.PROFILES.size() * 2:
		var idx: int = run % MechFactory.PROFILES.size()
		var site: Array = sites[1 + (run - MechFactory.PROFILES.size()) % (sites.size() - 1)] if run >= MechFactory.PROFILES.size() else sites[0]
		var n: String = "%s@%s" % [PROFILE_NAMES[idx], site[0]]
		var spawn: Vector3 = site[1]
		if site[0] == "open":
			spawn = Vector3(rng.randf_range(-20, 20), 0.2, rng.randf_range(10, 40))
		var m := await _spawn(idx, spawn)
		var bound := m.profile.max_en / m.profile.hover_cost_per_sec + sqrt(2.0 * 40.0 / m.profile.gravity) + 3.0
		var max_air := 0.0
		var penetrations := 0
		var out_of_bounds := 0
		var nan_frames := 0
		var counts := {}
		var seg_left := 0.0
		var mv := Vector3.ZERO
		var asc := false
		var dsc := false
		var t := 0.0
		var max_y := 0.0
		while t < 60.0:
			seg_left -= DT
			if seg_left <= 0.0:
				seg_left = rng.randf_range(0.1, 1.2)
				var a := rng.randf() * TAU
				mv = Vector3(cos(a), 0, sin(a)) * (0.0 if rng.randf() < 0.15 else 1.0)
				asc = rng.randf() < 0.45
				dsc = not asc and rng.randf() < 0.2
				if rng.randf() < 0.3:
					m.command.jump_pressed = true
				if rng.randf() < 0.35:
					m.command.dash_pressed = true
			m.command.move = mv
			m.command.ascend = asc
			m.command.descend = dsc
			await get_tree().physics_frame
			t += DT
			var p := m.global_position
			if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
				nan_frames += 1
				continue
			if p.y < -0.1 or p.y > GrayboxBuilder.CEILING_Y - MechMotor.BODY_HEIGHT + 0.6 or absf(p.x) > 99.5 or absf(p.z) > 99.5:
				out_of_bounds += 1
			max_y = maxf(max_y, p.y)
			max_air = maxf(max_air, m.air_time)
			counts[m.get_state_name()] = counts.get(m.get_state_name(), 0) + 1
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = probe_shape
			q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * MechMotor.BODY_HEIGHT * 0.5)
			q.collision_mask = 1
			if not space.intersect_shape(q, 1).is_empty():
				penetrations += 1
		_info("[%s] frames per state %s, max feet y %.1f, max air time %.2fs (bound %.2fs)" % [n, counts, max_y, max_air, bound])
		_check(res, nan_frames == 0, "[%s] no NaN positions" % n)
		_check(res, out_of_bounds == 0, "[%s] stayed inside floor / ceiling / side bounds (%d bad frames)" % [n, out_of_bounds])
		_check(res, penetrations == 0, "[%s] no geometry penetration (%d frames)" % [n, penetrations])
		_check(res, max_air <= bound, "[%s] no infinite air time: max %.2fs ≤ %.2fs" % [n, max_air, bound])
		_check(res, counts.size() >= 7, "[%s] exercised %d / 8 motion states" % [n, counts.size()])
		m.queue_free()
		await _ticks(2)


func t09_combat_layer(res: Dictionary) -> void:
	var m := await _spawn(0, GrayboxBuilder.POINTS.spawn)
	var combat := m.get_node("CombatStateMachine") as CombatStateMachine
	var go := func(dir: Vector3) -> Callable:
		return func(mm: MechMotor, _t: float) -> void:
			mm.command.move = dir
	await _sim(m, 1.0, go.call(Vector3(0, 0, -1)))
	combat.start_action(1.0)
	var en_before := m.en
	m.command.dash_pressed = true
	await _sim(m, 0.8, go.call(Vector3(1, 0, 0)))
	var v_action := m.get_horizontal_velocity()
	_check(res, v_action.length() > 1.0, "ACTION keeps movement control (speed %.1f m/s, %.0f%% of max)" % [v_action.length(), 100.0 * v_action.length() / m.profile.ground_max_speed])
	_check(res, v_action.x > 0.0, "ACTION still steers toward input (vx %.1f)" % v_action.x)
	_check(res, m.en >= en_before - 0.01, "ACTION blocks dash (EN %.1f → %.1f)" % [en_before, m.en])
	await _sim(m, 0.6, go.call(Vector3(1, 0, 0)))
	_check(res, combat.state == CombatStateMachine.CombatState.READY and not m.has_modifier(CombatStateMachine.MOD_ACTION), "ACTION modifier expired, combat READY")
	await _sim(m, 1.0, go.call(Vector3(1, 0, 0)))
	_check(res, m.get_horizontal_velocity().length() > m.profile.ground_max_speed * 0.95, "full speed restored after ACTION (%.1f)" % m.get_horizontal_velocity().length())
	_clear(m)
	await _enter_hover(m)
	m.en = m.profile.max_en
	var y0 := m.global_position.y
	combat.apply_stagger(0.5, Vector3(6, 0, 0))
	var en_s := m.en
	var up := func(mm: MechMotor, _t: float) -> void:
		mm.command.ascend = true
	await _sim(m, 0.45, up)
	_check(res, m.global_position.y < y0 - 0.5, "STAGGER in air blocks thrust: dropped %.2f m while ascend held" % (y0 - m.global_position.y))
	_check(res, is_equal_approx(m.en, en_s), "no EN spent while thrust blocked (%.1f → %.1f)" % [en_s, m.en])
	await _sim(m, 0.4, up)
	_check(res, m.velocity.y > 0.0 or m.is_grounded_state(), "control returns after STAGGER (state %s, vy %.1f)" % [m.get_state_name(), m.velocity.y])
	_clear(m)
	var idle := func(_mm: MechMotor, _t: float) -> void:
		pass
	await _sim(m, 4.0, idle)
	await _sim(m, 2.0, idle)
	m.en = m.profile.max_en
	await _enter_hover(m)
	var s := {"landed": false}
	var spam := func(mm: MechMotor, t: float) -> void:
		mm.command.ascend = true
		if fmod(t, 0.7) < DT:
			combat.start_action(0.6, 0.4, false)
	var probe := func(mm: MechMotor, _t: float) -> void:
		if mm.is_grounded_state():
			s.landed = true
	await _sim(m, 15.0, spam, probe)
	_check(res, s.landed, "spamming actions while holding ascend still ends on the ground (EN-limited)")
	var src := FileAccess.get_file_as_string("res://scripts/combat/combat_state_machine.gd")
	var rx := RegEx.create_from_string("velocity\\s*[+\\-*/]?=")
	_check(res, rx.search(src) == null, "combat_state_machine.gd contains no velocity assignment (static check)")
	m.queue_free()
	await _ticks(2)


## Pinhole projection matching Camera3D (keep height) at 16:9.
func _ndc(cam: Camera3D, p: Vector3) -> Vector3:
	var lp := cam.global_transform.affine_inverse() * p
	if lp.z >= -0.01:
		return Vector3(9, 9, -1)
	var ty := tan(deg_to_rad(cam.fov) * 0.5)
	return Vector3((lp.x / -lp.z) / (ty * 16.0 / 9.0), (lp.y / -lp.z) / ty, 1)


func _reset_stats(st: Dictionary) -> void:
	st.frames = 0
	st.tgt_in = 0
	st.ply_in = 0
	st.max_rate = 0.0
	st.tele_frames = 0
	st.tele_in = 0


func t10_camera_lock(res: Dictionary) -> void:
	await _rebuild_arena(true)
	var m := await _spawn(0, GrayboxBuilder.POINTS.spawn)
	var targeting := TargetingSystem.new()
	m.add_child(targeting)
	var rig := CameraRig.new()
	rig.mouse_enabled = false
	arena.add_child(rig)
	targeting.setup(m, rig.camera)
	rig.setup(m, targeting)
	var t3 := arena.get_node("Graybox/T3_bobbing") as Node3D
	targeting._set_target(t3, "test")
	var idle := func(_mm: MechMotor, _t: float) -> void:
		pass
	await _sim(m, 1.5, idle)
	var st := {}
	_reset_stats(st)
	st.prev_q = rig.camera.global_basis.get_rotation_quaternion()
	var probe := func(mm: MechMotor, _t: float) -> void:
		var cam := rig.camera
		var tn := _ndc(cam, targeting.get_target_point())
		var pn := _ndc(cam, mm.global_position + Vector3.UP * 2.5)
		st.frames += 1
		var t_in := tn.z > 0 and absf(tn.x) <= 0.9 and absf(tn.y) <= 0.9
		if t_in:
			st.tgt_in += 1
		if pn.z > 0 and absf(pn.x) <= 0.9 and absf(pn.y) <= 0.9:
			st.ply_in += 1
		var tt := targeting.current as TestTarget
		if tt and tt.telegraphing:
			st.tele_frames += 1
			if t_in:
				st.tele_in += 1
		var q := cam.global_basis.get_rotation_quaternion()
		if st.frames > 1:  # first frame after a reset only seeds prev_q
			st.max_rate = maxf(st.max_rate, rad_to_deg((st.prev_q as Quaternion).angle_to(q)) / DT)
		st.prev_q = q
	await _sim(m, 14.0, idle, probe)
	var r1 := st.duplicate()
	_reset_stats(st)
	m.command.jump_pressed = true
	var strafe := func(mm: MechMotor, t: float) -> void:
		var to := targeting.get_target_point() - mm.global_position
		mm.command.move = Vector3(-to.z, 0, to.x).normalized()
		mm.command.face_dir = to
		mm.command.ascend = t < 2.0
		mm.command.descend = t > 6.0
	await _sim(m, 10.0, strafe, probe)
	var r2 := st.duplicate()
	for pair in [["stationary, target bobbing ±12 m", r1], ["strafing + takeoff/landing", r2]]:
		var r: Dictionary = pair[1]
		var tgt_pct: float = 100.0 * r.tgt_in / maxf(r.frames, 1)
		var ply_pct: float = 100.0 * r.ply_in / maxf(r.frames, 1)
		var tele_pct: float = 100.0 * r.tele_in / maxf(r.tele_frames, 1)
		_info("%s: target in safe frame %.1f%%, player %.1f%%, telegraph visible %.1f%% of %d frames, max cam rotation %.0f°/s" % [pair[0], tgt_pct, ply_pct, tele_pct, r.tele_frames, r.max_rate])
		_check(res, tgt_pct >= 95.0, "%s: locked target inside 90%% safe frame ≥95%% of frames (%.1f%%)" % [pair[0], tgt_pct])
		_check(res, ply_pct >= 98.0, "%s: player inside safe frame ≥98%% (%.1f%%)" % [pair[0], ply_pct])
		_check(res, r.tele_frames > 0 and tele_pct >= 95.0, "%s: attack telegraph visible ≥95%% (%.1f%%)" % [pair[0], tele_pct])
		_check(res, r.max_rate <= rig.lock_max_turn_deg + 40.0, "%s: camera rotation ≤ %.0f°/s (max %.0f)" % [pair[0], rig.lock_max_turn_deg + 40.0, r.max_rate])
	_clear(m)
	await _sim(m, 3.0, idle)
	# cornered: back against TowerA while locked on the high target — camera
	# must not collapse into the mech and the player must stay visible
	m.reset_to(Vector3(37.2, 0.2, -23.1))
	targeting._set_target(arena.get_node("Graybox/T2_high"), "test")
	rig.snap()
	await _sim(m, 1.5, idle)
	_reset_stats(st)
	await _sim(m, 1.0, idle, probe)
	var cam_d := rig.camera.global_position.distance_to(m.global_position + Vector3.UP * rig.focus_height)
	_info("cornered vs T2_high: arm %.2f m, target on screen %.0f%%, player %.0f%%" % [cam_d, 100.0 * st.tgt_in / maxf(st.frames, 1), 100.0 * st.ply_in / maxf(st.frames, 1)])
	_check(res, cam_d >= 2.0 and st.ply_in == st.frames, "cornered against tower: arm %.2f m ≥ 2.0, player on screen %d/%d frames" % [cam_d, st.ply_in, st.frames])
	# height-difference target switching from open ground
	m.reset_to(GrayboxBuilder.POINTS.spawn)
	targeting._set_target(arena.get_node("Graybox/T3_bobbing"), "test")
	rig.snap()
	await _sim(m, 1.5, idle)
	for nm: String in ["T5_ground", "T2_high", "T1_low-hover", "T6_tower"]:
		var tgt := arena.get_node("Graybox/" + nm) as Node3D
		targeting._set_target(tgt, "test_switch")
		_reset_stats(st)
		await _sim(m, 1.0, idle, probe)
		var settle_rate: float = st.max_rate
		_info("switch %s: cam %s mech %s target %s blend %.2f" % [nm, rig.camera.global_position.snapped(Vector3.ONE * 0.1), m.global_position.snapped(Vector3.ONE * 0.1), targeting.get_target_point(tgt), rig.lock_blend])
		_reset_stats(st)
		await _sim(m, 1.2, idle, probe)
		var dh := targeting.get_target_point(tgt).y - m.global_position.y
		var dist := targeting.get_target_point(tgt).distance_to(m.global_position)
		var in_pct: float = 100.0 * st.tgt_in / maxf(st.frames, 1)
		var pl_pct: float = 100.0 * st.ply_in / maxf(st.frames, 1)
		_check(res, settle_rate <= rig.lock_max_turn_deg + 40.0, "switch to %s (Δh %+.1f m, %.0f m): transition rotation ≤ %.0f°/s (max %.0f)" % [nm, dh, dist, rig.lock_max_turn_deg + 40.0, settle_rate])
		_check(res, in_pct >= 95.0 and pl_pct >= 95.0 and st.max_rate < 30.0, "switch to %s: settled, target %.0f%% / player %.0f%% on screen, residual rotation %.1f°/s" % [nm, in_pct, pl_pct, st.max_rate])
	var space := get_viewport().world_3d.direct_space_state
	var sph := SphereShape3D.new()
	sph.radius = 0.2
	targeting._set_target(null, "test")
	m.reset_to(Vector3(0, 0.2, -42.5))
	rig.yaw = 0.0
	rig.snap()
	var so := {"inside": 0, "occl": 0}
	var back := func(mm: MechMotor, t: float) -> void:
		mm.command.move = Vector3(0, 0, 1) if t < 1.0 else Vector3.ZERO
	var probe_o := func(_mm: MechMotor, _t: float) -> void:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = sph
		q.transform = Transform3D(Basis.IDENTITY, rig.camera.global_position)
		q.collision_mask = 1
		if not space.intersect_shape(q, 1).is_empty():
			so.inside += 1
		if rig.occluded:
			so.occl += 1
	await _sim(m, 3.0, back, probe_o)
	_check(res, so.occl > 0 and so.inside == 0, "wall behind player: pulled in on %d frames, camera inside geometry %d frames" % [so.occl, so.inside])
	m.reset_to(GrayboxBuilder.POINTS.slab_under)
	rig.snap()
	so.inside = 0
	so.occl = 0
	m.command.jump_pressed = true
	var up := func(mm: MechMotor, _t: float) -> void:
		mm.command.ascend = true
	await _sim(m, 2.5, up, probe_o)
	_check(res, so.inside == 0, "under 0.4 m slab while thrusting: camera inside geometry %d frames (occluded %d)" % [so.inside, so.occl])
	rig.queue_free()
	m.queue_free()
	await _ticks(2)


func t11_targeting(res: Dictionary) -> void:
	await _rebuild_arena(true)
	var m := await _spawn(0, GrayboxBuilder.POINTS.spawn)
	var targeting := TargetingSystem.new()
	m.add_child(targeting)
	var rig := CameraRig.new()
	rig.mouse_enabled = false
	arena.add_child(rig)
	targeting.setup(m, rig.camera)
	rig.setup(m, targeting)
	var events: Array[String] = []
	targeting.target_changed.connect(func(_o: Node3D, nw: Node3D, reason: String) -> void:
		events.append("%s:%s" % [nw.name if nw else "none", reason]))
	await _ticks(10)
	targeting.toggle_lock()
	_check(res, targeting.has_target(), "acquire picked %s" % (targeting.current.name if targeting.current else "none"))
	var first := targeting.current
	targeting.cycle(1)
	var second := targeting.current
	targeting.cycle(-1)
	_check(res, second != first and targeting.current == first, "cycle next/prev: %s → %s → %s" % [first.name, second.name, targeting.current.name])
	(targeting.current as TestTarget).kill()
	await _ticks(3)
	_check(res, targeting.has_target() and targeting.current != first and events[-1].ends_with("auto_switch"), "destroyed target → auto switch (%s)" % events[-1])
	_check(res, not TeamRules.get_valid_targets(m).has(first), "destroyed target no longer a valid target")
	m.reset_to(Vector3(95, 0.2, 95))
	targeting.lose_range = 60.0
	await _ticks(5)
	_check(res, not targeting.has_target() and targeting.last_lost_reason == "out_of_range", "out of range → unlocked (%s)" % targeting.last_lost_reason)
	targeting.lose_range = 175.0
	m.reset_to(Vector3(40, 0.2, -86))
	await _ticks(20)
	targeting._set_target(arena.get_node("Graybox/T6_tower"), "test")
	var s := {"lost": -1.0}
	var idle := func(_mm: MechMotor, _t: float) -> void:
		pass
	var probe := func(_mm: MechMotor, t: float) -> void:
		if s.lost < 0 and not targeting.has_target():
			s.lost = t
	await _sim(m, 4.0, idle, probe)
	_check(res, s.lost > 0.0 and absf(s.lost - targeting.lose_los_time) < 0.2 and targeting.last_lost_reason == "occluded", "occluded (behind tower) → unlocked at %.2fs, limit %.1fs (%s)" % [s.lost, targeting.lose_los_time, targeting.last_lost_reason])
	var ally := TestTarget.new()
	ally.team_id = 0
	ally.position = m.global_position + Vector3(0, 3, -8)
	arena.add_child(ally)
	await _ticks(2)
	_check(res, not TeamRules.get_valid_targets(m).has(ally), "same-team dummy excluded via TeamRules.is_hostile")
	_info("events: %s" % ", ".join(events))
	rig.queue_free()
	m.queue_free()
	await _ticks(2)


func t12_pursuit_support(res: Dictionary) -> void:
	## Supporting evidence only for M03 (stays DEFERRED: needs hook claw /
	## melee skills + AI from later phases). Checks the shared motor alone lets
	## the heaviest-inertia melee frame close on a hovering target.
	await _rebuild_arena(true)
	var m := await _spawn(2, GrayboxBuilder.POINTS.spawn)
	var target := arena.get_node("Graybox/T1_low-hover") as Node3D
	var s := {"best": 999.0, "reach": -1.0, "dashed": false}
	m.command.jump_pressed = true
	var chase := func(mm: MechMotor, t: float) -> void:
		var to := target.global_position - (mm.global_position + Vector3.UP * 2.0)
		var hz := Vector3(to.x, 0, to.z)
		mm.command.move = hz.normalized() if hz.length() > 2.0 else Vector3.ZERO
		mm.command.ascend = to.y > 0.5
		mm.command.descend = to.y < -1.5
		if not s.dashed and t > 0.4 and hz.length() > 12.0:
			mm.command.dash_pressed = true
			s.dashed = true
	var probe := func(mm: MechMotor, t: float) -> void:
		var d := (mm.global_position + Vector3.UP * 2.0).distance_to(target.global_position)
		s.best = minf(s.best, d)
		if s.reach < 0 and d < 4.0:
			s.reach = t
	await _sim(m, 6.0, chase, probe)
	_info("hellfang reached within %.2f m of the 6 m-high target at t=%.2fs (scripted chase, not AI)" % [s.best, s.reach])
	_check(res, s.reach > 0.0, "movement alone closes to <4 m of a hovering target (supporting evidence only)")
	m.queue_free()
	await _ticks(2)


func _evasion_run(target: TestTarget, m: MechMotor, shots: int, mode: String) -> Dictionary:
	## mode: hold | air_dash | descend | strafe | reverse
	## Evasive actions are triggered REACTION seconds after the shot is fired
	## (telegraph end), i.e. reacting to the visible shot, not pre-dodging.
	const REACTION := 0.05
	TestProjectile.reset_stats()
	var s := {"was": target.telegraphing, "dir": 1.0, "fired0": target.shots_fired, "fire_t": -100.0, "acted": true, "flipped_mid": true}
	var drive := func(mm: MechMotor, _t: float) -> void:
		mm.en = mm.profile.max_en  # harness keeps EN topped up to isolate evasion
		var fired_now: bool = s.was and not target.telegraphing
		s.was = target.telegraphing
		if fired_now:
			if TestProjectile.debug_print:
				print("[fire] mech %s vel %s" % [mm.global_position.snapped(Vector3.ONE * 0.1), mm.velocity.snapped(Vector3.ONE * 0.1)])
			s.fire_t = target.time
			s.acted = false
			s.flipped_mid = false
		var since: float = target.time - s.fire_t
		mm.command.move = Vector3.ZERO
		mm.command.descend = false
		var want_alt := 10.0 if mode == "descend" else 6.0
		mm.command.ascend = mm.global_position.y < want_alt and since > 1.0
		if mm.command.ascend and mm.is_grounded_state():
			mm.command.jump_pressed = true
		if mode == "strafe" or mode == "reverse" or mode == "air_dash":
			if not s.flipped_mid and since >= 2.0:
				s.dir = -s.dir  # mid-cycle turn keeps the mech inside the arena
				s.flipped_mid = true
		if mode == "strafe" or mode == "reverse":
			mm.command.move = Vector3(s.dir, 0, 0)
		if not s.acted and since >= REACTION:
			s.acted = true
			match mode:
				"air_dash":
					mm.command.move = Vector3(s.dir, 0, 0)
					mm.command.dash_pressed = true
				"reverse":
					s.dir = -s.dir
					mm.command.move = Vector3(s.dir, 0, 0)
		if mode == "descend" and since >= REACTION and since < REACTION + 0.6:
			mm.command.descend = true
			mm.command.ascend = false
	var until := func(_mm: MechMotor, _t: float) -> bool:
		return target.shots_fired - int(s.fired0) >= shots
	await _sim(m, shots * target.telegraph_interval + 6.0, drive, Callable(), until)
	var tail := func(mm: MechMotor, _t: float) -> void:
		drive.call(mm, _t)
	await _sim(m, 3.5, tail)  # let the last shot resolve (out-of-range takes ~2.9 s)
	_clear(m)
	return {"fired": target.shots_fired - int(s.fired0), "hits": TestProjectile.hits, "dodges": TestProjectile.dodges}


func t13_air_evasion(res: Dictionary) -> void:
	## Supporting evidence for M04 (manual item). Uses the grey-box shooter
	## fixture (no damage system). Shooter T1 hovers at 6 m, player ~30 m away.
	await _rebuild_arena(true)
	var target := arena.get_node("Graybox/T1_low-hover") as TestTarget
	target.shooting_enabled = true
	var results := {}
	for mode: String in ["hold", "air_dash", "descend"]:
		var m := await _spawn(0, Vector3(0, 0.2, 15))
		await _enter_hover(m)
		if mode == "descend":
			var climb := func(mm: MechMotor, _t: float) -> void:
				mm.command.ascend = mm.global_position.y < 10.0
			await _sim(m, 1.0, climb)
		results[mode] = await _evasion_run(target, m, 4, mode)
		m.queue_free()
		await _ticks(2)
	target.lead_target = true
	for mode: String in ["strafe", "reverse"]:
		var m := await _spawn(0, Vector3(0, 0.2, 15))
		await _enter_hover(m)
		results["lead_" + mode] = await _evasion_run(target, m, 4, mode)
		m.queue_free()
		await _ticks(2)
	for k in results:
		var r: Dictionary = results[k]
		_info("%-14s fired %d  hits %d  dodged %d" % [k, r.fired, r.hits, r.dodges])
	for k in results:
		_check(res, results[k].hits + results[k].dodges == results[k].fired, "%s: every shot resolved (%d fired)" % [k, results[k].fired])
	_check(res, results.hold.fired == 4 and results.hold.hits >= 3, "control: hovering still is hit by aimed shots (%d/4)" % results.hold.hits)
	_check(res, results.air_dash.hits <= 1, "lateral air dash at the telegraph dodges (%d/4 hit)" % results.air_dash.hits)
	_check(res, results.descend.hits <= 1, "controlled descent at the telegraph dodges (%d/4 hit)" % results.descend.hits)
	_check(res, results.lead_strafe.hits >= 3, "control: leading shot hits a constant strafe (%d/4)" % results.lead_strafe.hits)
	_check(res, results.lead_reverse.hits <= 1, "direction change before the shot beats the lead (%d/4 hit)" % results.lead_reverse.hits)
