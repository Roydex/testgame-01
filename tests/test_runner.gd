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
		["T14", "C01 hit detection: active frames only, one hit per attack", t14_hit_detection],
		["T15", "C02 damage system: single resolver, permissions", t15_damage_system],
		["T16", "C03 combo chain, input buffer, cancel window", t16_combo],
		["T17", "C04 guard / guard break / parry / whiff / reflect", t17_defence],
		["T18", "C05 hit reactions: hitstop, stagger, knockback, airborne", t18_reactions],
		["T19", "C06 telegraphs + hard-control protection", t19_telegraph_cc],
		["T20", "C07 anti-air: limited vertical tracking, no teleport", t20_anti_air],
		["T21", "C08 death, invalid target, restart", t21_death_restart],
		["T22", "C10 shared components player / sparring partner", t22_shared_components],
		["T23", "C11 ultimate: unlock, windup, judgment, spear, overload", t23_ultimate],
		["T24", "C12 melee rules: arc, local hitstop, multi-parry, ownership", t24_melee_rules],
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
	# static architecture check: no combat-layer file writes a mech's velocity
	# (writes to MovementModifier.forced_velocity — the motion-correction
	# interface — are allowed)
	var rx := RegEx.create_from_string("(?<![\\w.])velocity\\s*[+\\-*/]?=(?!=)|motor\\.velocity\\s*[+\\-*/]?=(?!=)")
	for f: String in ["combat_state_machine.gd", "damage_system.gd", "ultimate_system.gd"]:
		var src := FileAccess.get_file_as_string("res://scripts/combat/" + f)
		_check(res, rx.search(src) == null, "%s writes no mech velocity (static check)" % f)
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
	# distance presets (Z key): cycle near/mid/far, eased, no jumps
	_clear(m)
	m.reset_to(GrayboxBuilder.POINTS.spawn)
	rig.distance_preset_index = 1
	rig.snap()
	await _sim(m, 0.5, idle)
	var arm_of := func() -> float:
		return rig.camera.global_position.distance_to(m.global_position + Vector3.UP * rig.focus_height)
	for expect: float in [13.0, 7.5, 10.0]:
		var got := rig.cycle_distance()
		var sz := {"max_step": 0.0, "prev": arm_of.call()}
		var probe_z := func(_mm: MechMotor, _t: float) -> void:
			var a: float = arm_of.call()
			sz.max_step = maxf(sz.max_step, absf(a - sz.prev))
			sz.prev = a
		await _sim(m, 1.5, idle, probe_z)
		var arm: float = arm_of.call()
		# arm = base distance plus shoulder offset (hypotenuse)
		var want := sqrt(expect * expect + rig.shoulder_offset * rig.shoulder_offset)
		_check(res, is_equal_approx(got, expect) and absf(arm - want) < 0.3 and sz.max_step < 0.5,
			"zoom preset %.1f m: arm %.2f (expected %.2f), largest per-frame change %.2f m (eased)" % [expect, arm, want, sz.max_step])
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



# ======================================================================
# Phase 2b combat tests
# ======================================================================

const SERAPH := "res://resources/combat/pale_seraph_combat.tres"
const RANGED := "res://resources/combat/sparring_ranged_combat.tres"

var _rec_conns: Array = []


func _fighter(combat_path: String, team: int, pos: Vector3, look := Vector3.INF) -> MechMotor:
	var m := MechFactory.create_mech(MechFactory.load_profile(1), team, Color.GRAY, false, load(combat_path))
	m.position = pos
	if look != Vector3.INF:
		m.rotation.y = atan2(-(look.x - pos.x), -(look.z - pos.z))
	arena.add_child(m)
	return m


func _cs(m: Node) -> CombatStateMachine:
	return m.get_node(^"CombatStateMachine") as CombatStateMachine


func _record() -> Dictionary:
	var ev := {"hits": [], "attacks": [], "telegraphs": [], "parries": [], "ult": [], "deaths": [], "frame": 0}
	var c1 := func(h: HitInfo) -> void: ev.hits.append([ev.frame, h, h.result, h.final_damage])
	var c2 := func(a: Node3D, d: AttackDefinition) -> void: ev.attacks.append([ev.frame, a, d.id])
	var c3 := func(a: Node3D, d: AttackDefinition, t: float) -> void: ev.telegraphs.append([ev.frame, a, d.id if d else &"ultimate_windup", t])
	var c4 := func(d: Node3D, a: Node3D, p: bool) -> void: ev.parries.append([ev.frame, d, a, p])
	var c5 := func(m: Node3D, ph: String) -> void: ev.ult.append([ev.frame, m, ph])
	var c6 := func(m: Node3D) -> void: ev.deaths.append([ev.frame, m])
	CombatEvents.hit_resolved.connect(c1)
	CombatEvents.attack_started.connect(c2)
	CombatEvents.telegraph.connect(c3)
	CombatEvents.parried.connect(c4)
	CombatEvents.ultimate_phase.connect(c5)
	CombatEvents.mech_died.connect(c6)
	_rec_conns = [[CombatEvents.hit_resolved, c1], [CombatEvents.attack_started, c2], [CombatEvents.telegraph, c3],
		[CombatEvents.parried, c4], [CombatEvents.ultimate_phase, c5], [CombatEvents.mech_died, c6]]
	return ev


func _unrecord() -> void:
	for c in _rec_conns:
		(c[0] as Signal).disconnect(c[1])
	_rec_conns.clear()


## Steps n physics frames, running `each` (optional) before every frame.
func _frames(ev: Dictionary, n: int, each := Callable()) -> void:
	for i in n:
		if each.is_valid():
			each.call(i)
		await get_tree().physics_frame
		ev.frame += 1


func _hits_on(ev: Dictionary, victim: Node) -> Array:
	var out := []
	for h in ev.hits:
		if (h[1] as HitInfo).victim == victim:
			out.append(h)
	return out


func _face(m: MechMotor, at: Node3D) -> void:
	var to := at.global_position - m.global_position
	m.command.face_dir = Vector3(to.x, 0, to.z)


func t14_hit_detection(res: Dictionary) -> void:
	var a := _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
	var b := _fighter(SERAPH, 1, Vector3(0, 0.2, 26.5), Vector3(0, 0.2, 30))
	await _ticks(20)
	var ev := _record()
	a.command.attack_pressed = true
	_cs(a).aim_target = b
	await _frames(ev, 40)
	var hb := _hits_on(ev, b)
	var l1 := load("res://resources/combat/seraph_l1.tres") as AttackDefinition
	var first_f: int = hb[0][0] if hb.size() > 0 else -1
	var t_first := first_f * DT
	_check(res, hb.size() == 1, "single L1 press: exactly 1 hit on the target (%d)" % hb.size())
	_check(res, hb.size() > 0 and t_first >= l1.windup - DT and t_first <= l1.windup + l1.active + DT,
		"hit landed at %.3fs, inside the active window [%.2f, %.2f]" % [t_first, l1.windup, l1.windup + l1.active])
	# out of range / behind / ally
	var cases := [["out of range (12 m ahead)", Vector3(0, 0.2, 18), 1], ["behind the attacker", Vector3(0, 0.2, 33.5), 1], ["same team in range", Vector3(0, 0.2, 26.5), 0]]
	for c in cases:
		b.queue_free()
		await _ticks(2)
		b = _fighter(SERAPH, c[2], c[1], Vector3(0, 0.2, 30))
		await _ticks(30)
		var hp0 := _cs(b).health.hp
		var ev2 := _record()
		a.command.attack_pressed = true
		_cs(a).aim_target = null
		await _frames(ev2, 40)
		var any_hit := false
		for h in _hits_on(ev2, b):
			if h[2] != CombatTypes.HitResult.IGNORED:
				any_hit = true
		_unrecord()
		_check(res, not any_hit and is_equal_approx(_cs(b).health.hp, hp0), "%s: no damage (HP %.0f)" % [c[0], _cs(b).health.hp])
	_unrecord()
	a.queue_free()
	b.queue_free()
	await _ticks(2)


func t15_damage_system(res: Dictionary) -> void:
	var a := _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
	var b := _fighter(SERAPH, 1, Vector3(0, 0.2, 26.5), Vector3(0, 0.2, 30))
	await _ticks(20)
	var ev := _record()
	var hp0 := _cs(b).health.hp
	_cs(a).aim_target = b
	var spam := func(i: int) -> void:
		if i % 12 == 0:
			a.command.attack_pressed = true
	await _frames(ev, 120, spam)
	var total := 0.0
	var resolved := 0
	for h in _hits_on(ev, b):
		total += h[3]
		resolved += 1
	_check(res, resolved >= 2 and absf((hp0 - _cs(b).health.hp) - total) < 0.01,
		"HP lost %.2f == sum of DamageSystem final_damage %.2f over %d hits" % [hp0 - _cs(b).health.hp, total, resolved])
	var l1 := load("res://resources/combat/seraph_l1.tres") as AttackDefinition
	_check(res, resolved > 0 and is_equal_approx(_hits_on(ev, b)[0][3], l1.damage), "first hit = L1 data damage %.1f" % l1.damage)
	# direct resolve: same team and dead victims are ignored
	var ally := _fighter(SERAPH, 0, Vector3(5, 0.2, 30))
	await _ticks(5)
	var hi := HitInfo.new()
	hi.attacker = a
	hi.victim = ally
	hi.attack = l1
	hi.source_position = a.global_position
	_check(res, DamageSystem.resolve(hi) == CombatTypes.HitResult.IGNORED and is_equal_approx(_cs(ally).health.hp, _cs(ally).health.max_hp),
		"same team: TeamRules.can_damage blocks the hit")
	_cs(b).health.take(_cs(b).health.hp)
	var hd := HitInfo.new()
	hd.attacker = a
	hd.victim = b
	hd.attack = l1
	hd.source_position = a.global_position
	_check(res, DamageSystem.resolve(hd) == CombatTypes.HitResult.IGNORED, "dead victim: hit ignored")
	_unrecord()
	for n in [a, b, ally]:
		n.queue_free()
	await _ticks(2)


func t16_combo(res: Dictionary) -> void:
	var a := _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
	await _ticks(20)
	var l1 := load("res://resources/combat/seraph_l1.tres") as AttackDefinition
	var l2 := l1.next_attack
	var l3 := l2.next_attack
	var ev := _record()
	var presses := func(i: int) -> void:
		if i == 0 or i == 9 or i == 22:
			a.command.attack_pressed = true
	await _frames(ev, 90, presses)
	var ids := []
	var starts := []
	for e in ev.attacks:
		if e[1] == a:
			ids.append(e[2])
			starts.append(e[0] * DT)
	_info("combo starts: %s at %s" % [ids, starts])
	_check(res, ids == [&"seraph_l1", &"seraph_l2", &"seraph_l3"], "3 buffered presses chain L1 → L2 → L3")
	var exp2 := l1.windup + l1.active
	var exp3 := exp2 + l2.windup + l2.active
	_check(res, starts.size() == 3 and absf(starts[1] - exp2) <= 2.0 * DT and absf(starts[2] - exp3) <= 2.0 * DT,
		"chain points at %.2fs / %.2fs (data %.2f / %.2f)" % [starts[1] if starts.size() > 1 else -1.0, starts[2] if starts.size() > 2 else -1.0, exp2, exp3])
	await _frames(ev, 40)
	_check(res, _cs(a).state == CombatStateMachine.CombatState.READY, "back to READY after the finisher")
	# single press: no chain
	ev.attacks.clear()
	a.command.attack_pressed = true
	await _frames(ev, 60)
	_check(res, ev.attacks.size() == 1, "single press: only L1 (%d attacks)" % ev.attacks.size())
	# cancel window: dash before cancel_time is blocked, after it cancels the recovery
	a.command.attack_pressed = true
	await _frames(ev, 1)
	var st := {"dash_early": false}
	var early := func(i: int) -> void:
		if i == 3:
			a.command.dash_pressed = true
	await _frames(ev, int(l1.cancel_time / DT) - 3, early)
	st.dash_early = a.state == MechMotor.MotionState.GROUND_DASH
	_check(res, not st.dash_early and _cs(a).state == CombatStateMachine.CombatState.ATTACK, "dash before cancel window ignored (still %s)" % _cs(a).get_state_name())
	await _frames(ev, 10)
	a.command.dash_pressed = true
	await _frames(ev, 3)
	_check(res, a.state == MechMotor.MotionState.GROUND_DASH and _cs(a).state == CombatStateMachine.CombatState.READY,
		"dash inside cancel window cancels recovery (%s / %s)" % [a.get_state_name(), _cs(a).get_state_name()])
	_unrecord()
	a.queue_free()
	await _ticks(2)


## A attacks B with L1; `defend.call(frame)` drives B. Returns the hit entries on B.
func _duel(a: MechMotor, b: MechMotor, frames: int, defend: Callable, attack_frame: int = 10) -> Dictionary:
	var ev := _record()
	_cs(a).aim_target = b
	var drive := func(i: int) -> void:
		_face(b, a)
		_face(a, b)
		if i == attack_frame:
			a.command.attack_pressed = true
		defend.call(i)
	await _frames(ev, frames, drive)
	_unrecord()
	return ev


func t17_defence(res: Dictionary) -> void:
	var cp := load(SERAPH) as CombatProfile
	var l1 := cp.light_combo
	# --- guard (frontal)
	var a := _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
	var b := _fighter(SERAPH, 1, Vector3(0, 0.2, 26.5), Vector3(0, 0.2, 30))
	await _ticks(20)
	var en0 := b.en
	var guard := func(_i: int) -> void:
		b.command.guard_held = true
	var ev := await _duel(a, b, 40, guard)
	var h := _hits_on(ev, b)
	_check(res, h.size() > 0 and h[0][2] == CombatTypes.HitResult.GUARDED and is_equal_approx(h[0][3], l1.damage * cp.guard_damage_taken),
		"frontal guard: GUARDED, chip %.2f (= %.0f × %.2f)" % [h[0][3] if h.size() else -1.0, l1.damage, cp.guard_damage_taken])
	_check(res, absf((en0 - b.en) - l1.damage * cp.guard_en_per_damage) < 0.5, "guard drains EN %.1f (expected %.1f)" % [en0 - b.en, l1.damage * cp.guard_en_per_damage])
	# --- guard with no EN -> break
	await _ticks(60)
	var guard_no_en := func(_i: int) -> void:
		b.command.guard_held = true
		b.en = 0.0
	ev = await _duel(a, b, 40, guard_no_en)
	h = _hits_on(ev, b)
	_check(res, h.size() > 0 and h[0][2] == CombatTypes.HitResult.GUARD_BREAK and _cs(b).state == CombatStateMachine.CombatState.STAGGER or (h.size() > 0 and h[0][2] == CombatTypes.HitResult.GUARD_BREAK),
		"guard without EN breaks (%s)" % (CombatTypes.RESULT_NAMES[h[0][2]] if h.size() else "no hit"))
	a.queue_free()
	b.queue_free()
	await _ticks(90)
	# --- parry melee inside the window
	a = _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
	b = _fighter(SERAPH, 1, Vector3(0, 0.2, 26.5), Vector3(0, 0.2, 30))
	await _ticks(20)
	var hp_b := _cs(b).health.hp
	var parry_at := func(i: int) -> void:
		if i == 13:  # attack at 10, active from +7 frames, window 9 frames
			b.command.parry_pressed = true
	ev = await _duel(a, b, 20, parry_at)
	h = _hits_on(ev, b)
	_check(res, h.size() > 0 and h[0][2] == CombatTypes.HitResult.PARRIED and is_equal_approx(_cs(b).health.hp, hp_b),
		"parry in window: PARRIED, defender HP unchanged (%.0f)" % _cs(b).health.hp)
	_check(res, _cs(a).state == CombatStateMachine.CombatState.OFFBALANCE and _cs(a).offbalance_by == b,
		"attacker knocked OFF-BALANCE by the parrier (%s)" % _cs(a).get_state_name())
	# counter window: the parrier's first hit deals ×1.5 and cannot be guarded
	var hp_a := _cs(a).health.hp
	var ev3 := _record()
	_cs(b).aim_target = a
	var punish := func(i: int) -> void:
		_face(b, a)
		if i == 0:
			b.command.attack_pressed = true
		a.command.guard_held = true
	await _frames(ev3, 25, punish)
	var ha := _hits_on(ev3, a)
	_unrecord()
	_check(res, ha.size() > 0 and ha[0][2] == CombatTypes.HitResult.HIT and is_equal_approx(hp_a - _cs(a).health.hp, l1.damage * cp.counter_damage_mult),
		"punish hit on off-balance attacker: %.1f dmg (= ×%.1f), guard ignored" % [hp_a - _cs(a).health.hp, cp.counter_damage_mult])
	a.queue_free()
	b.queue_free()
	await _ticks(90)
	# --- whiffed parry: recovery takes ×1.2
	a = _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
	b = _fighter(SERAPH, 1, Vector3(0, 0.2, 26.5), Vector3(0, 0.2, 30))
	await _ticks(20)
	hp_b = _cs(b).health.hp
	var early := func(i: int) -> void:
		if i == 6:  # window ends before the active frames, recovery covers them
			b.command.parry_pressed = true
	ev = await _duel(a, b, 30, early)
	h = _hits_on(ev, b)
	_check(res, h.size() > 0 and h[0][2] == CombatTypes.HitResult.HIT and is_equal_approx(hp_b - _cs(b).health.hp, l1.damage * cp.parry_whiff_damage_mult),
		"whiffed parry: hit during recovery for %.1f (= ×%.1f)" % [hp_b - _cs(b).health.hp, cp.parry_whiff_damage_mult])
	a.queue_free()
	b.queue_free()
	await _ticks(2)
	# --- projectile parry -> reflected back to the shooter
	var s := _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
	var r := _fighter(RANGED, 1, Vector3(0, 0.2, 10), Vector3(0, 0.2, 30))
	await _ticks(20)
	var hp_r := _cs(r).health.hp
	var ev4 := _record()
	_cs(r).aim_target = s
	var st := {"parried": false}
	var shoot := func(i: int) -> void:
		_face(s, r)
		_face(r, s)
		if i == 2:
			r.command.attack_pressed = true
		if not st.parried:
			for p in get_tree().get_nodes_in_group(&"projectiles"):
				if (p as Node3D).global_position.distance_to(s.global_position + Vector3.UP * 2.5) < 6.0:
					s.command.parry_pressed = true
					st.parried = true
	await _frames(ev4, 150, shoot)
	_unrecord()
	var refl := false
	for e in ev4.hits:
		if (e[1] as HitInfo).victim == s and e[2] == CombatTypes.HitResult.REFLECTED:
			refl = true
	var pulse := (load(RANGED) as CombatProfile).ranged
	_check(res, refl, "projectile parried by the mirror shield: REFLECTED")
	_check(res, is_equal_approx(hp_r - _cs(r).health.hp, pulse.damage * cp.reflect_damage_mult),
		"reflected shot hit its shooter for %.1f (= %.0f × %.1f)" % [hp_r - _cs(r).health.hp, pulse.damage, cp.reflect_damage_mult])
	s.queue_free()
	r.queue_free()
	await _ticks(2)


func t18_reactions(res: Dictionary) -> void:
	var cp := load(SERAPH) as CombatProfile
	var l3 := cp.light_combo.next_attack.next_attack
	var a := _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
	var b := _fighter(SERAPH, 1, Vector3(0, 0.2, 26.5), Vector3(0, 0.2, 30))
	await _ticks(20)
	var ev := _record()
	_cs(a).aim_target = b
	var st := {"stop_a": 0, "stop_b": 0, "stag": 0, "z0": b.global_position.z}
	var drive := func(i: int) -> void:
		_face(a, b)
		if i in [0, 9, 22]:
			a.command.attack_pressed = true
		if a.in_hitstop(): st.stop_a += 1
		if b.in_hitstop(): st.stop_b += 1
		if _cs(b).state == CombatStateMachine.CombatState.STAGGER: st.stag += 1
	await _frames(ev, 120, drive)
	_unrecord()
	var hits := _hits_on(ev, b)
	_check(res, hits.size() == 3, "3-hit combo connected (%d)" % hits.size())
	_check(res, st.stop_a > 0 and st.stop_b > 0, "hitstop on both attacker (%d f) and victim (%d f)" % [st.stop_a, st.stop_b])
	_check(res, absf(b.global_position.z - st.z0) > 1.5, "knockback displaced the victim %.2f m" % absf(b.global_position.z - st.z0))
	_check(res, st.stag > int(l3.stagger_time * 0.5 / DT), "victim spent %d frames in STAGGER" % st.stag)
	a.queue_free()
	b.queue_free()
	await _ticks(2)
	# airborne victim: stagger blocks thrust, it falls
	a = _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
	b = _fighter(SERAPH, 1, Vector3(0, 0.2, 26.5), Vector3(0, 0.2, 30))
	await _ticks(20)
	b.command.jump_pressed = true
	var hold := func(i: int) -> void:
		b.command.ascend = i < 20
	var ev2 := _record()
	await _frames(ev2, 50, hold)
	var y0 := b.global_position.y
	_cs(b).apply_stagger(0.6, Vector3(3, 0, 0))
	var asc := func(_i: int) -> void:
		b.command.ascend = true
	await _frames(ev2, 30, asc)
	_unrecord()
	_check(res, b.global_position.y < y0 - 0.5, "airborne stagger: thrust blocked while holding ascend, dropped %.2f m" % (y0 - b.global_position.y))
	a.queue_free()
	b.queue_free()
	await _ticks(2)


func t19_telegraph_cc(res: Dictionary) -> void:
	# data rule: every major attack is telegraphed with a perceivable windup
	var exempt := {&"seraph_judgment_counter": "only after a successful parry (attacker already off-balance)"}
	var defs := []
	for f in DirAccess.get_files_at("res://resources/combat"):
		var r := load("res://resources/combat/" + f)
		if r is AttackDefinition:
			defs.append(r)
	for d: AttackDefinition in defs:
		var major := d.damage >= 14.0 or d.guard_break or d.stagger_time >= 0.35
		if not major:
			continue
		if exempt.has(d.id):
			_info("%s exempt: %s" % [d.id, exempt[d.id]])
			continue
		_check(res, d.telegraphed and d.windup >= 0.2, "major attack %s telegraphed with %.2fs windup" % [d.id, d.windup])
	# runtime: telegraph event fires at windup start
	var a := _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
	await _ticks(20)
	var ev := _record()
	a.command.skill_pressed = true
	await _frames(ev, 5)
	_check(res, ev.telegraphs.size() == 1 and ev.telegraphs[0][2] == &"seraph_dash_slash" and ev.telegraphs[0][0] <= 1,
		"dash slash broadcasts its telegraph on the first frame")
	_unrecord()
	await _ticks(90)
	# hard-control protection
	var c := _cs(a)
	var durs := []
	for k in 5:
		var before := c.state_timer
		var was_immune := c.cc_immune_left > 0.0
		c.apply_stagger(1.0)
		var applied := c.state_timer if not is_equal_approx(c.state_timer, before) else 0.0
		durs.append("immune" if (was_immune or c.cc_immune_left > 0.0) and applied == 0.0 else snappedf(applied, 0.01))
		await _ticks(24)
	_info("consecutive 1.0 s staggers every 0.4 s → %s" % [durs])
	_check(res, is_equal_approx(float(durs[0]), 1.0) and float(durs[1]) < 1.0 and float(durs[2]) < float(durs[1]) and durs[3] == "immune" and durs[4] == "immune",
		"diminishing durations, then CC immunity (%s)" % [durs])
	a.queue_free()
	await _ticks(2)
	# 1v2: two attackers alternating combos cannot keep the victim locked
	var v := _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
	var e1 := _fighter(SERAPH, 1, Vector3(-2, 0.2, 26.8))
	var e2 := _fighter(SERAPH, 2, Vector3(2, 0.2, 26.8))
	_cs(v).health.max_hp = 99999.0
	_cs(v).health.hp = 99999.0
	await _ticks(20)
	var ev2 := _record()
	var st := {"cc": 0, "run": 0, "max_run": 0}
	var gank := func(i: int) -> void:
		_face(e1, v)
		_face(e2, v)
		_cs(e1).aim_target = v
		_cs(e2).aim_target = v
		if i % 12 == 0:
			e1.command.attack_pressed = true
		if i % 12 == 6:
			e2.command.attack_pressed = true
		var s2 := _cs(v).state
		if s2 == CombatStateMachine.CombatState.STAGGER or s2 == CombatStateMachine.CombatState.OFFBALANCE:
			st.cc += 1
			st.run += 1
			st.max_run = maxi(st.max_run, st.run)
		else:
			st.run = 0
	await _frames(ev2, 600, gank)
	_unrecord()
	var pct: float = 100.0 * st.cc / 600.0
	_info("1v2 continuous pressure for 10 s: victim hard-controlled %.0f%% of frames, longest chain %.2fs, %d hits" % [pct, st.max_run * DT, _hits_on(ev2, v).size()])
	_check(res, pct <= 70.0 and st.max_run * DT <= 2.0, "no permanent lock: CC %.0f%% ≤ 70%%, longest chain %.2fs ≤ 2.0s" % [pct, st.max_run * DT])
	for n in [v, e1, e2]:
		n.queue_free()
	await _ticks(2)


func t20_anti_air(res: Dictionary) -> void:
	var ds := (load(SERAPH) as CombatProfile).skill
	for case in [["target hovering 5 m up, 11 m away", 5.0, true], ["target hovering 14 m up (beyond tracking range)", 14.0, false]]:
		var a := _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
		var b := _fighter(SERAPH, 1, Vector3(0, 0.2, 19))
		await _ticks(20)
		# put b in a hover at the requested height (harness keeps EN topped up)
		b.command.jump_pressed = true
		var climb := func(_i: int) -> void:
			b.en = b.profile.max_en
			b.command.ascend = b.global_position.y < case[1]
		var ev0 := _record()
		await _frames(ev0, 150, climb)
		_unrecord()
		var ev := _record()
		_cs(a).aim_target = b
		var st := {"max_step": 0.0, "max_vy": 0.0, "prev": a.global_position}
		var go := func(i: int) -> void:
			b.en = b.profile.max_en
			b.command.ascend = b.global_position.y < case[1]
			_face(a, b)
			if i == 0:
				a.command.skill_pressed = true
			var p: Vector3 = a.global_position
			st.max_step = maxf(st.max_step, p.distance_to(st.prev))
			st.max_vy = maxf(st.max_vy, a.velocity.y)
			st.prev = p
		await _frames(ev, 70, go)
		_unrecord()
		var hit := false
		for h in _hits_on(ev, b):
			if h[2] == CombatTypes.HitResult.HIT:
				hit = true
		_info("%s: hit %s, attacker max step %.2f m/frame, max climb %.1f m/s" % [case[0], hit, st.max_step, st.max_vy])
		_check(res, hit == case[2], "%s → %s" % [case[0], "reached and hit" if case[2] else "not reachable (no hit)"])
		_check(res, st.max_step <= ds.lunge_speed * DT * 1.15 + 0.05 and st.max_vy <= ds.vertical_track_speed + 0.5,
			"%s: no teleport/suction (step %.2f ≤ %.2f m, climb %.1f ≤ %.1f m/s)" % [case[0], st.max_step, ds.lunge_speed * DT * 1.15 + 0.05, st.max_vy, ds.vertical_track_speed + 0.5])
		a.queue_free()
		b.queue_free()
		await _ticks(2)


func t21_death_restart(res: Dictionary) -> void:
	var a := _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
	var b := _fighter(SERAPH, 1, Vector3(0, 0.2, 26.5), Vector3(0, 0.2, 30))
	b.add_to_group(&"lock_targets")
	var tg := TargetingSystem.new()
	a.add_child(tg)
	tg.setup(a, null)
	await _ticks(20)
	tg._set_target(b, "test")
	var ev := _record()
	_cs(b).health.hp = 5.0
	_cs(a).aim_target = b
	var drive := func(i: int) -> void:
		_face(a, b)
		if i == 0:
			a.command.attack_pressed = true
	await _frames(ev, 30, drive)
	_check(res, ev.deaths.size() == 1 and ev.deaths[0][1] == b and _cs(b).is_dead(), "HP 0 → mech_died event, state DEAD")
	_check(res, not TeamRules.get_valid_targets(a, &"mechs").has(b) and not b.is_alive(), "dead mech is no longer a valid target")
	_check(res, not tg.has_target(), "lock released on death (last reason: %s)" % tg.last_lost_reason)
	var hp_dead := _cs(b).health.hp
	b.command.attack_pressed = true
	ev.hits.clear()
	a.command.attack_pressed = true
	await _frames(ev, 30)
	_check(res, _hits_on(ev, b).size() == 0 or _hits_on(ev, b)[0][2] == CombatTypes.HitResult.IGNORED, "hits on the wreck are ignored")
	_check(res, _cs(b).is_dead() and _cs(b).attack == null and is_equal_approx(_cs(b).health.hp, hp_dead), "dead mech accepts no actions")
	_unrecord()
	a.queue_free()
	b.queue_free()
	await _ticks(2)
	# restart: the playable scene rebuilt from scratch has full HP everywhere
	var scene_res := load("res://scenes/test/graybox_test.tscn") as PackedScene
	var sc := scene_res.instantiate()
	add_child(sc)
	await _ticks(10)
	var pc := sc.get("combat") as CombatStateMachine
	pc.health.take(pc.health.hp)
	await _ticks(5)
	_check(res, pc.is_dead() and (sc.get("combat_hud") as CombatHud)._overlay.visible, "player death shows the restart overlay")
	sc.queue_free()
	await _ticks(3)
	var sc2 := scene_res.instantiate()
	add_child(sc2)
	await _ticks(10)
	var pc2 := sc2.get("combat") as CombatStateMachine
	var ok := not pc2.is_dead() and is_equal_approx(pc2.health.hp, pc2.health.max_hp)
	for d in sc2.get("dummies"):
		ok = ok and _cs(d).health.hp == _cs(d).health.max_hp
	_check(res, ok, "restart (fresh scene instance): player and sparring partners at full HP")
	sc2.queue_free()
	await _ticks(3)


func t22_shared_components(res: Dictionary) -> void:
	var sc := (load("res://scenes/test/graybox_test.tscn") as PackedScene).instantiate()
	add_child(sc)
	await _ticks(10)
	var player := sc.get("motor") as MechMotor
	var comps := func(m: Node) -> Array:
		var out := []
		for c in m.get_children():
			var cls: String = (c.get_script() as Script).get_global_name() if c.get_script() else c.get_class()
			if cls in ["PlayerBrain", "SparringBrain", "MechVisual", "TargetingSystem"]:
				continue
			out.append(cls)
		out.sort()
		return out
	var pset: Array = comps.call(player)
	_info("player components: %s" % [pset])
	for d in sc.get("dummies"):
		var dset: Array = comps.call(d)
		var dm := d as MechMotor
		var same_core: bool = dset.has("CombatStateMachine") and dset.has("Health") and dset.has("Hurtbox") and dm.get_script() == player.get_script()
		_check(res, same_core, "%s shares MechMotor + CombatStateMachine + Health + Hurtbox with the player (%s)" % [d.name, dset])
		_check(res, d.get_node_or_null(^"SparringBrain") != null and d.get_node_or_null(^"PlayerBrain") == null, "%s differs only by its brain (SparringBrain)" % d.name)
	var melee := (sc.get("dummies") as Array)[0] as MechMotor
	_check(res, pset == comps.call(melee), "melee partner (same PALE SERAPH kit) has the identical component set incl. UltimateSystem")
	# the partner acts only through MechCommand: it moves / attacks in the real scene
	var p0 := melee.global_position
	var ev := _record()
	await _frames(ev, 240)
	_unrecord()
	var attacked := false
	for e in ev.attacks:
		if e[1] == melee:
			attacked = true
	_check(res, melee.global_position.distance_to(p0) > 2.0 and attacked, "partner moved %.1f m and attacked via MechCommand" % melee.global_position.distance_to(p0))
	sc.queue_free()
	await _ticks(3)


func _low_hp(m: MechMotor) -> void:
	var c := _cs(m)
	c.health.take(c.health.hp - c.health.max_hp * 0.29)


func t23_ultimate(res: Dictionary) -> void:
	var ud := (load(SERAPH) as CombatProfile).ultimate
	var a := _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
	await _ticks(20)
	var u := _cs(a).ultimate
	var ev := _record()
	a.command.ult_pressed = true
	await _frames(ev, 10)
	_check(res, u.phase == UltimateSystem.Phase.LOCKED and _cs(a).state == CombatStateMachine.CombatState.READY, "HP 100%: ultimate LOCKED, V does nothing")
	_low_hp(a)
	await _frames(ev, 2)
	_check(res, u.phase == UltimateSystem.Phase.READY, "HP 29%% ≤ %d%%: READY" % int(ud.hp_threshold * 100))
	a.command.ult_pressed = true
	var st := {"windup_f": 0}
	var count := func(_i: int) -> void:
		if u.phase == UltimateSystem.Phase.WINDUP:
			st.windup_f += 1
	await _frames(ev, 30, count)
	_check(res, absf(st.windup_f * DT - ud.windup) <= 2.0 * DT and u.in_judgment(), "windup %.2fs (data %.2f) → JUDGMENT" % [st.windup_f * DT, ud.windup])
	var tele := false
	for t in ev.telegraphs:
		if t[1] == a and t[2] == &"ultimate_windup":
			tele = true
	_check(res, tele, "ultimate windup is telegraphed to everyone")
	# judgment buffs: speed and dash cost
	var run := func(_i: int) -> void:
		a.command.move = Vector3(1, 0, 0)
	await _frames(ev, 60, run)
	var spd := a.get_horizontal_velocity().length()
	_check(res, absf(spd - a.profile.ground_max_speed * ud.speed_mult) < 0.3, "JUDGMENT speed %.1f m/s (= %.0f × %.2f)" % [spd, a.profile.ground_max_speed, ud.speed_mult])
	var en0 := a.en
	a.command.dash_pressed = true
	await _frames(ev, 2, run)
	_check(res, absf((en0 - a.en) - a.profile.ground_dash_cost * ud.dash_cost_mult) < 0.6, "JUDGMENT dash cost %.1f EN (= %.0f × %.1f)" % [en0 - a.en, a.profile.ground_dash_cost, ud.dash_cost_mult])
	_clear(a)
	await _frames(ev, 30)
	# parry window doubled
	a.command.parry_pressed = true
	var pw := {"f": 0}
	var countp := func(_i: int) -> void:
		if _cs(a).is_parrying():
			pw.f += 1
	await _frames(ev, 30, countp)
	var cp := load(SERAPH) as CombatProfile
	_check(res, absf(pw.f * DT - cp.parry_window * ud.parry_window_mult) <= 2.0 * DT, "JUDGMENT parry window %.2fs (= %.2f × %.0f)" % [pw.f * DT, cp.parry_window, ud.parry_window_mult])
	# spear: 2 charges inside JUDGMENT (wait out the whiffed-parry recovery first)
	await _frames(ev, 30)
	var ids := []
	for k in 2:
		ev.attacks.clear()
		a.command.skill_pressed = true
		await _frames(ev, 3)
		if ev.attacks.size() > 0:
			ids.append(ev.attacks[0][2])
		await _frames(ev, 145)
	_info("skill presses in JUDGMENT: %s (charges left %d, %.1fs of judgment left)" % [ids, u.spear_charges_left, u.phase_time_left])
	_check(res, ids == [&"seraph_final_spear", &"seraph_final_spear"] and u.spear_charges_left == 0, "two 终审之矛 charges in JUDGMENT")
	# overload: EN does not regenerate, damage taken ×1.3
	var ov := {"seen": false, "en_rise": false, "en": 0.0, "mult": 1.0}
	var watch := func(_i: int) -> void:
		if u.phase == UltimateSystem.Phase.OVERLOAD:
			if not ov.seen:
				ov.seen = true
				a.en = 20.0
				ov.en = 20.0
				ov.mult = _cs(a).damage_taken_mult()
			elif a.en > ov.en + 0.01:
				ov.en_rise = true
	await _frames(ev, int((u.phase_time_left + ud.overload_duration + 0.5) / DT), watch)
	_check(res, ov.seen and not ov.en_rise, "OVERLOAD reached and EN did not regenerate during it")
	_check(res, is_equal_approx(ov.mult, ud.overload_damage_taken_mult), "OVERLOAD damage taken ×%.1f" % ov.mult)
	_check(res, u.phase == UltimateSystem.Phase.SPENT, "after overload: SPENT (uses_per_match %d)" % ud.uses_per_match)
	ev.attacks.clear()
	a.command.skill_pressed = true
	await _frames(ev, 3)
	_check(res, ev.attacks.size() > 0 and ev.attacks[0][2] == &"seraph_dash_slash", "after the ultimate the skill is the normal dash slash again")
	var tl := []
	for e in ev.ult:
		tl.append("%s@%.2f" % [e[2], e[0] * DT])
	_info("ultimate timeline: %s" % [tl])
	await _frames(ev, 60)
	a.command.ult_pressed = true
	await _frames(ev, 5)
	_check(res, u.phase == UltimateSystem.Phase.SPENT and _cs(a).state != CombatStateMachine.CombatState.ULT_WINDUP, "once per match: V does nothing afterwards")
	_unrecord()
	a.queue_free()
	await _ticks(2)

	# windup parries frontal melee and enters judgment immediately
	a = _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
	var b := _fighter(SERAPH, 1, Vector3(0, 0.2, 26.5), Vector3(0, 0.2, 30))
	await _ticks(20)
	_low_hp(a)
	await _ticks(2)
	var ev2 := _record()
	var wp := func(i: int) -> void:
		_face(a, b)
		_face(b, a)
		_cs(b).aim_target = a
		if i == 0:
			b.command.attack_pressed = true
		if i == 4:
			a.command.ult_pressed = true
	await _frames(ev2, 20, wp)
	var hres := _hits_on(ev2, a)
	_check(res, hres.size() > 0 and hres[0][2] == CombatTypes.HitResult.PARRIED and _cs(a).ultimate.in_judgment(),
		"frontal hit during the windup is parried → JUDGMENT at once (%s)" % (CombatTypes.RESULT_NAMES[hres[0][2]] if hres.size() else "no hit"))
	# judgment counter: next melee parry triggers 裁决反击 on the attacker
	await _frames(ev2, 50)
	ev2.attacks.clear()
	ev2.hits.clear()
	var jc := func(i: int) -> void:
		_face(a, b)
		_face(b, a)
		if i == 0:
			b.command.attack_pressed = true
		if i == 5:
			a.command.parry_pressed = true
	await _frames(ev2, 40, jc)
	var countered := false
	for e in ev2.attacks:
		if e[1] == a and e[2] == &"seraph_judgment_counter":
			countered = true
	var counter_hit := false
	for h in _hits_on(ev2, b):
		if (h[1] as HitInfo).attack.id == &"seraph_judgment_counter" and h[2] == CombatTypes.HitResult.HIT:
			counter_hit = true
	_check(res, countered and counter_hit, "JUDGMENT melee parry auto-triggers 裁决反击 and it lands")
	_unrecord()
	a.queue_free()
	b.queue_free()
	await _ticks(2)

	# flank hit interrupts the windup → COOLDOWN, then READY again
	a = _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
	b = _fighter(SERAPH, 1, Vector3(3.5, 0.2, 30), Vector3(0, 0.2, 30))
	a.rotation.y = 0.0  # facing -Z, b is on its right flank
	await _ticks(20)
	_low_hp(a)
	await _ticks(2)
	var ev3 := _record()
	var fl := func(i: int) -> void:
		_face(b, a)
		_cs(b).aim_target = a
		if i == 0:
			b.command.attack_pressed = true
		if i == 3:
			a.command.ult_pressed = true
	await _frames(ev3, 20, fl)
	_check(res, _cs(a).ultimate.phase == UltimateSystem.Phase.COOLDOWN, "flank hit during the windup interrupts it → COOLDOWN (%s)" % _cs(a).ultimate.get_phase_name())
	await _frames(ev3, int(ud.interrupt_cooldown / DT) + 5)
	_check(res, _cs(a).ultimate.phase == UltimateSystem.Phase.READY, "interrupted ultimate becomes READY again after %.0fs" % ud.interrupt_cooldown)
	# parry activation: V right after a successful parry skips the windup
	ev3.ult.clear()
	var pa := func(i: int) -> void:
		_face(a, b)
		_face(b, a)
		if i == 0:
			b.command.attack_pressed = true
		if i == 5:
			a.command.parry_pressed = true
		if i == 14:
			a.command.ult_pressed = true
	await _frames(ev3, 30, pa)
	var phases := []
	for e in ev3.ult:
		if e[1] == a:
			phases.append(e[2])
	_check(res, _cs(a).ultimate.in_judgment() and not phases.has("WINDUP"), "parry-activation: JUDGMENT without windup (%s)" % [phases])
	_unrecord()
	a.queue_free()
	b.queue_free()
	await _ticks(2)

	# spear stops at walls; a sidestep at the telegraph dodges it
	a = _fighter(SERAPH, 0, Vector3(0, 0.2, -25))
	b = _fighter(SERAPH, 1, Vector3(0, 0.2, -50))  # behind the thick wall (z = -40)
	await _ticks(20)
	_low_hp(a)
	await _ticks(2)
	_cs(a).ultimate.enter_judgment()
	_cs(a).aim_target = b
	var ev4 := _record()
	var spear := func(i: int) -> void:
		_face(a, b)
		if i == 0:
			a.command.skill_pressed = true
	await _frames(ev4, 150, spear)
	_check(res, a.global_position.z > -40.0 and _hits_on(ev4, b).size() == 0, "spear stopped by the wall (attacker z %.1f, wall -40), no hit through cover" % a.global_position.z)
	_unrecord()
	a.queue_free()
	b.queue_free()
	await _ticks(2)
	for dodge in [false, true]:
		a = _fighter(SERAPH, 0, Vector3(0, 0.2, 40))
		b = _fighter(SERAPH, 1, Vector3(0, 0.2, 12))
		await _ticks(20)
		_low_hp(a)
		await _ticks(2)
		_cs(a).ultimate.enter_judgment()
		_cs(a).aim_target = b
		var ev5 := _record()
		var sp2 := func(i: int) -> void:
			_face(a, b)
			if i == 0:
				a.command.skill_pressed = true
			if dodge and i == 40:  # during the 1.0 s charge
				b.command.move = Vector3(1, 0, 0)
				b.command.dash_pressed = true
			elif dodge and i > 40:
				b.command.move = Vector3(1, 0, 0)
		await _frames(ev5, 120, sp2)
		var landed := false
		for h in _hits_on(ev5, b):
			if h[2] == CombatTypes.HitResult.HIT:
				landed = true
		_check(res, landed != dodge, "spear vs %s → %s" % ["sidestep at the telegraph" if dodge else "standing target", "dodged" if dodge else "hit"])
		_unrecord()
		a.queue_free()
		b.queue_free()
		await _ticks(2)

	# the sparring partner uses the same ultimate interface on its own
	var sc := (load("res://scenes/test/graybox_test.tscn") as PackedScene).instantiate()
	add_child(sc)
	await _ticks(10)
	var melee := (sc.get("dummies") as Array)[0] as MechMotor
	_low_hp(melee)
	var player := sc.get("motor") as MechMotor
	_cs(player).health.max_hp = 99999.0
	_cs(player).health.hp = 99999.0
	var ev6 := _record()
	await _frames(ev6, 600)
	_unrecord()
	var dummy_phases := []
	for e in ev6.ult:
		if e[1] == melee:
			dummy_phases.append(e[2])
	_check(res, dummy_phases.has("JUDGMENT"), "sparring partner unlocked and used the ultimate via MechCommand (%s)" % [dummy_phases])
	sc.queue_free()
	await _ticks(3)


func t24_melee_rules(res: Dictionary) -> void:
	# frontal arc: parry / guard do not cover the flank
	for mode in ["parry", "guard"]:
		var v := _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
		var e := _fighter(SERAPH, 1, Vector3(3.5, 0.2, 30), Vector3(0, 0.2, 30))
		v.rotation.y = 0.0
		await _ticks(20)
		var ev := _record()
		var drv := func(i: int) -> void:
			_face(e, v)
			_cs(e).aim_target = v
			v.command.face_dir = Vector3(0, 0, -1)
			if i == 0:
				e.command.attack_pressed = true
			if mode == "parry" and i == 3:
				v.command.parry_pressed = true
			if mode == "guard":
				v.command.guard_held = true
		await _frames(ev, 20, drv)
		_unrecord()
		var h := _hits_on(ev, v)
		_check(res, h.size() > 0 and h[0][2] == CombatTypes.HitResult.HIT, "%s does not cover a 90° flank attack (%s)" % [mode, CombatTypes.RESULT_NAMES[h[0][2]] if h.size() else "no hit"])
		v.queue_free()
		e.queue_free()
		await _ticks(2)
	# local hitstop: a third mech keeps moving while two are frozen
	var a := _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
	var b := _fighter(SERAPH, 1, Vector3(0, 0.2, 26.5), Vector3(0, 0.2, 30))
	var c := _fighter(SERAPH, 2, Vector3(15, 0.2, 30))
	await _ticks(20)
	var ev2 := _record()
	var st := {"frozen": 0, "c_moved": 0.0, "prev": c.global_position}
	var drv2 := func(i: int) -> void:
		_face(a, b)
		_cs(a).aim_target = b
		c.command.move = Vector3(0, 0, -1)
		if i == 0:
			a.command.attack_pressed = true
		if a.in_hitstop() and b.in_hitstop():
			st.frozen += 1
			st.c_moved += c.global_position.distance_to(st.prev)
		st.prev = c.global_position
	await _frames(ev2, 40, drv2)
	_unrecord()
	_check(res, st.frozen > 0 and st.c_moved > 0.1, "during %d hitstop frames of A/B the third mech moved %.2f m" % [st.frozen, st.c_moved])
	for n in [a, b, c]:
		n.queue_free()
	await _ticks(2)
	# two attackers in one parry window: first PARRIED (off-balance), second DEFLECTED
	var v2 := _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
	var e1 := _fighter(SERAPH, 1, Vector3(-1.4, 0.2, 26.8), Vector3(0, 0.2, 30))
	var e2 := _fighter(SERAPH, 2, Vector3(1.4, 0.2, 26.8), Vector3(0, 0.2, 30))
	v2.rotation.y = 0.0
	await _ticks(20)
	var ev3 := _record()
	var drv3 := func(i: int) -> void:
		v2.command.face_dir = Vector3(0, 0, -1)
		for e in [e1, e2]:
			_face(e, v2)
			_cs(e).aim_target = v2
			if i == 0:
				e.command.attack_pressed = true
		if i == 4:
			v2.command.parry_pressed = true
	await _frames(ev3, 20, drv3)
	_unrecord()
	var results := []
	for h in _hits_on(ev3, v2):
		results.append(CombatTypes.RESULT_NAMES[h[2]])
	var offb := int(_cs(e1).state == CombatStateMachine.CombatState.OFFBALANCE) + int(_cs(e2).state == CombatStateMachine.CombatState.OFFBALANCE)
	_check(res, results.has("PARRIED") and results.has("DEFLECTED") and offb == 1, "simultaneous attackers: %s, %d attacker off-balance" % [results, offb])
	for n in [v2, e1, e2]:
		n.queue_free()
	await _ticks(2)
	# reflected projectile ownership: FFA third party gets hit, ally is passed through
	for mode in ["FFA", "alliance"]:
		var s := _fighter(SERAPH, 0, Vector3(0, 0.2, 30))
		var r := _fighter(RANGED, 1, Vector3(0, 0.2, 6), Vector3(0, 0.2, 30))
		var third := _fighter(SERAPH, 2 if mode == "FFA" else 0, Vector3(0, 0.2, 14))
		await _ticks(20)
		# third party crouches out of the way until the shot is reflected
		third.global_position = Vector3(6, 0.2, 14)
		var hp_t := _cs(third).health.hp
		var hp_r := _cs(r).health.hp
		var ev4 := _record()
		_cs(r).aim_target = s
		var st2 := {"parried": false, "moved": false}
		var drv4 := func(i: int) -> void:
			_face(s, r)
			_face(r, s)
			if i == 2:
				r.command.attack_pressed = true
			for p in get_tree().get_nodes_in_group(&"projectiles"):
				var pp := p as Projectile
				if not st2.parried and pp.global_position.distance_to(s.global_position + Vector3.UP * 2.5) < 6.0:
					s.command.parry_pressed = true
					st2.parried = true
				if pp.reflected and not st2.moved:
					third.global_position = Vector3(0, 0.2, 14)  # step into the return path
					st2.moved = true
		await _frames(ev4, 150, drv4)
		_unrecord()
		var t_hit := not is_equal_approx(_cs(third).health.hp, hp_t)
		var r_hit := not is_equal_approx(_cs(r).health.hp, hp_r)
		if mode == "FFA":
			_check(res, st2.moved and t_hit, "FFA: reflected shot (now owned by the parrier) hits a hostile third party in its path")
		else:
			_check(res, st2.moved and not t_hit and r_hit, "alliance: reflected shot passes through the parrier's ally and hits the shooter")
		for n in [s, r, third]:
			n.queue_free()
		await _ticks(2)
