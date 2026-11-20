extends Node
## Phase 3a balance simulation (headless, fixed 60 Hz). Two experiments:
##  1. DPS probe: each mech is held at a fixed distance from a sparring
##     target (stationary / strafing + dashing) and fires its kit with a
##     simple scripted rotation for SAMPLE_S seconds. Records damage per
##     second, hit rate and the attacks that did the damage.
##  2. Scripted 1v1: every pair, both spawn sides, the generic scripted
##     partner pattern at full aggression (NOT an AI), up to MATCH_S s.
## These are scripted proxies, not player skill: use them for ranges and
## relative tendencies only. Output: tests/logs/balance_sim.log and
## tests/logs/balance_sim.json.
##   Godot --headless --path . --fixed-fps 60 res://tests/balance_sim.tscn

const DT := 1.0 / 60.0
const SAMPLE_S := 15.0
const MATCH_S := 90.0
const RANGES := [5.0, 12.0, 20.0, 30.0, 45.0]

var arena: Node3D
var out := {"dps": [], "duels": []}
var lines: PackedStringArray = []


func _ready() -> void:
	seed(20261119)
	_run.call_deferred()


## Each probe / duel gets its own fixed seed, so a change to one mech no
## longer reshuffles the random strafing of every later matchup (round-5
## diagnosis: one changed duel shifted all the following results).
func _seed_for(key: String) -> int:
	return 20261119 ^ key.hash()


func _log(s: String) -> void:
	print(s)
	lines.append(s)


func _new_arena() -> void:
	arena = Node3D.new()
	add_child(arena)
	GrayboxBuilder.build(arena, false)
	await get_tree().physics_frame


func _free_arena() -> void:
	arena.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _cs(m: Node) -> CombatStateMachine:
	return m.get_node(^"CombatStateMachine") as CombatStateMachine


func _run() -> void:
	_log("=== Phase 3a balance simulation  %s ===" % Time.get_datetime_string_from_system())
	_log("\n--- 1. DPS probe (damage per second while held at distance d; target does not defend)")
	_log("%-9s %-9s %6s %8s %8s  %s" % ["mech", "target", "d (m)", "DPS", "hit%", "damage by attack"])
	for id: StringName in MechFactory.MECH_IDS:
		for strafe in [false, true]:
			for d: float in RANGES:
				await _new_arena()
				seed(_seed_for("%s/%s/%d" % [id, strafe, int(d)]))
				var r := await _probe(id, d, strafe)
				await _free_arena()
				out.dps.append(r)
				_log("%-9s %-9s %6.0f %8.1f %7.0f%%  %s" % [id, "strafing" if strafe else "still", d, r.dps, r.hit_rate * 100.0, r.by_attack])
	_log("\n--- 2. Scripted 1v1 (full-aggression partner pattern, ultimates off; both spawn sides)")
	var ids := MechFactory.MECH_IDS
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			for side in 2:
				var a: StringName = ids[i] if side == 0 else ids[j]
				var b: StringName = ids[j] if side == 0 else ids[i]
				await _new_arena()
				seed(_seed_for("%s/%s" % [a, b]))
				var r := await _duel(a, b)
				await _free_arena()
				out.duels.append(r)
				_log("%-9s vs %-9s → winner %-9s  %5.1f s   HP left %s %.0f%% / %s %.0f%%   dmg %s" % [a, b, r.winner, r.time,
					a, r.hp_a * 100.0, b, r.hp_b * 100.0, r.damage])
	var f := FileAccess.open(ProjectSettings.globalize_path("res://tests/logs/balance_sim.log"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	var j := FileAccess.open(ProjectSettings.globalize_path("res://tests/logs/balance_sim.json"), FileAccess.WRITE)
	j.store_string(JSON.stringify(out, "  "))
	j.close()
	get_tree().quit()


# ------------------------------------------------------------------ 1. DPS probe

func _probe(id: StringName, d: float, strafe: bool) -> Dictionary:
	var tgt := MechFactory.create_by_id(&"seraph", 1, false)
	tgt.position = Vector3(0, 0.2, 0)
	arena.add_child(tgt)
	var a := MechFactory.create_by_id(id, 0, false)
	a.position = Vector3(0, 0.2, d)
	arena.add_child(a)
	await get_tree().physics_frame
	var tc := _cs(tgt)
	tc.health.setup(100000.0)
	var ac := _cs(a)
	ac.aim_target = tgt
	var st := {"dmg": 0.0, "hits": 0, "shots": 0, "by": {}, "dir": 1.0, "flip": 0.0}
	var on_hit := func(h: HitInfo) -> void:
		if h.victim == tgt and DamageSystem.is_landed(h.result) and (h.attacker == a or (h.attacker and h.attacker.get(&"owner_mech") == a)):
			st.dmg += h.final_damage
			st.hits += 1
			st.by[String(h.attack.id)] = snappedf(float(st.by.get(String(h.attack.id), 0.0)) + h.final_damage, 0.1)
	var on_start := func(m: Node3D, _def: AttackDefinition) -> void:
		if m == a:
			st.shots += 1
	CombatEvents.hit_resolved.connect(on_hit)
	CombatEvents.attack_started.connect(on_start)
	var t := 0.0
	var ctl := {"hold": 0, "kind": &""}
	while t < SAMPLE_S:
		_drive_attacker(a, tgt, d, ctl, t)
		if strafe:
			st.flip -= DT
			if st.flip <= 0.0:
				st.flip = randf_range(0.8, 1.6)
				st.dir = -st.dir
				tgt.command.dash_pressed = randf() < 0.5
			var to := a.global_position - tgt.global_position
			tgt.command.move = Vector3(to.z, 0, -to.x).normalized() * st.dir
		await get_tree().physics_frame
		t += DT
	CombatEvents.hit_resolved.disconnect(on_hit)
	CombatEvents.attack_started.disconnect(on_start)
	return {"mech": String(id), "range": d, "strafe": strafe, "dps": st.dmg / SAMPLE_S,
		"hit_rate": float(st.hits) / maxf(float(st.shots), 1.0), "by_attack": st.by}


## Scripted rotation per mech; keeps the attacker at distance `d` (no closing).
func _drive_attacker(a: MechMotor, tgt: MechMotor, d: float, ctl: Dictionary, t: float) -> void:
	var c := _cs(a)
	var cmd := a.command
	var to := tgt.global_position - a.global_position
	var flat := Vector3(to.x, 0, to.z)
	cmd.face_dir = flat
	c.aim_target = tgt
	var err := flat.length() - d
	cmd.move = flat.normalized() * clampf(err * 0.5, -1.0, 1.0) if absf(err) > 0.8 else Vector3.ZERO
	cmd.attack_held = false
	cmd.skill_held = false
	cmd.guard_held = false
	if ctl.hold <= 0 and c.is_aiming_placement():
		cmd.attack_pressed = true  # orbital marking: confirm at once (auto-call on the target)
		return
	if ctl.hold > 0:
		ctl.hold -= 1
		match ctl.kind:
			&"skill_hold": cmd.skill_held = true
			&"attack_hold": cmd.attack_held = true
			&"charge": cmd.guard_held = true
		return
	var p := c.profile
	var dist := flat.length()
	var ready := func(def: AttackDefinition) -> bool:
		return def != null and c.get_cooldown(def.id) <= 0.0 and c.kit.can_start(def)
	var mech_id: StringName = a.get_meta(&"mech_id")
	match mech_id:
		&"seraph":
			if dist > 6.0 and ready.call(p.skill):
				cmd.skill_pressed = true
			else:
				cmd.attack_pressed = fmod(t, 0.15) < DT
		&"hellfang":
			var hk := c.kit as HeatKit
			if hk.heat > 88.0 and ready.call(p.skill_hold):
				ctl.kind = &"skill_hold"; ctl.hold = 25; cmd.skill_pressed = true
			elif hk.heat >= 60.0 and dist < 14.0 and ready.call(p.attack_hold):
				ctl.kind = &"attack_hold"; ctl.hold = 25; cmd.attack_pressed = true; cmd.attack_held = true
			elif dist > 6.0 and dist < 25.0 and ready.call(p.skill):
				cmd.skill_pressed = true
			else:
				cmd.attack_pressed = fmod(t, 0.15) < DT
		&"verdant":
			if ready.call(p.skill):
				cmd.skill_pressed = true
			elif ready.call(p.skill_hold) and dist < 22.0:
				ctl.kind = &"skill_hold"; ctl.hold = 25; cmd.skill_pressed = true; cmd.skill_held = true
			else:
				cmd.attack_pressed = fmod(t, 0.15) < DT
		&"azure":
			if ready.call(p.skill_hold) and dist < 60.0:
				ctl.kind = &"skill_hold"; ctl.hold = 25; cmd.skill_pressed = true; cmd.skill_held = true
			elif ready.call(p.skill) and dist > 6.0:
				cmd.skill_pressed = true
			elif dist > 10.0 and fmod(t, 4.0) < DT and ready.call(p.charge_attack):
				ctl.kind = &"charge"; ctl.hold = int(c.profile.charge_time * 60.0) + 2; cmd.guard_held = true
			else:
				cmd.attack_pressed = fmod(t, 0.15) < DT


# ------------------------------------------------------------------ 2. duels

func _duel(ida: StringName, idb: StringName) -> Dictionary:
	var a := MechFactory.create_by_id(ida, 1, false)
	a.position = Vector3(0, 0.2, 20)
	arena.add_child(a)
	var b := MechFactory.create_by_id(idb, 2, false)
	b.position = Vector3(0, 0.2, -12)
	arena.add_child(b)
	for m in [a, b]:
		m.add_to_group(&"lock_targets")
		var br := SparringBrain.new()
		br.name = "SparringBrain"
		br.mode = SparringBrain.Mode.MELEE if (m == a and ida in [&"seraph", &"hellfang"]) or (m == b and idb in [&"seraph", &"hellfang"]) else SparringBrain.Mode.RANGED
		br.use_ultimate = false
		m.add_child(br)
		br.setup(m)
	var dmg := {String(ida) + "_dealt": 0.0, String(idb) + "_dealt": 0.0}
	var on_hit := func(h: HitInfo) -> void:
		var src: Node = h.attacker
		if src and src.get(&"owner_mech") is Node:
			src = src.get(&"owner_mech")
		if src == a:
			dmg[String(ida) + "_dealt"] += h.final_damage
		elif src == b:
			dmg[String(idb) + "_dealt"] += h.final_damage
	CombatEvents.hit_resolved.connect(on_hit)
	var t := 0.0
	while t < MATCH_S and TeamRules.is_alive(a) and TeamRules.is_alive(b):
		await get_tree().physics_frame
		t += DT
	CombatEvents.hit_resolved.disconnect(on_hit)
	var ha := _cs(a).health.ratio()
	var hb := _cs(b).health.ratio()
	var w := "timeout"
	if not TeamRules.is_alive(a):
		w = String(idb)
	elif not TeamRules.is_alive(b):
		w = String(ida)
	for k in dmg:
		dmg[k] = snappedf(dmg[k], 1.0)
	return {"a": String(ida), "b": String(idb), "winner": w, "time": t, "hp_a": ha, "hp_b": hb, "damage": dmg}
