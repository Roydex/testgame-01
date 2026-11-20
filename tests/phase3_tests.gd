extends RefCounted
## Phase 3a acceptance tests (P01–P11): the HELLFANG / VERDANT ARK / AZURE
## ORACLE kits. Driven by tests/test_runner.gd, which owns the arena and the
## shared helpers (r._check, r._frames, r._record …).
## NOTE: GDScript lambdas capture locals by value — mutable probe state lives
## in Dictionaries.

const DT := 1.0 / 60.0
const SERAPH := "res://resources/combat/pale_seraph_combat.tres"

var r: Node  # the test runner


func _init(runner: Node) -> void:
	r = runner


# ------------------------------------------------------------------ helpers

func _mech(id: StringName, team: int, pos: Vector3, look := Vector3.INF) -> MechMotor:
	var m := MechFactory.create_by_id(id, team, false)
	m.position = pos
	if look != Vector3.INF:
		m.rotation.y = atan2(-(look.x - pos.x), -(look.z - pos.z))
	r.arena.add_child(m)
	return m


func _cs(m: Node) -> CombatStateMachine:
	return m.get_node(^"CombatStateMachine") as CombatStateMachine


func _kit(m: Node) -> MechKit:
	return _cs(m).kit


func _aim(a: MechMotor, b: Node3D) -> void:
	_cs(a).aim_target = b
	var to := b.global_position - a.global_position
	a.command.face_dir = Vector3(to.x, 0, to.z)


## Event recorder for the phase-3 signals (plus hits / attacks).
var _conns: Array = []


func _rec() -> Dictionary:
	var ev := {"frame": 0, "hits": [], "started": [], "active": [], "finished": [], "telegraph": [], "kit": [],
		"area": [], "spawned": [], "removed": [], "status": []}
	var c := [
		[CombatEvents.hit_resolved, func(h: HitInfo) -> void: ev.hits.append([ev.frame, h, h.result, h.final_damage])],
		[CombatEvents.attack_started, func(a: Node3D, d: AttackDefinition) -> void: ev.started.append([ev.frame, a, d.id])],
		[CombatEvents.attack_active, func(a: Node3D, d: AttackDefinition) -> void: ev.active.append([ev.frame, a, d.id])],
		[CombatEvents.attack_finished, func(a: Node3D, d: AttackDefinition, l: bool) -> void: ev.finished.append([ev.frame, a, d.id, l])],
		[CombatEvents.telegraph, func(a: Node3D, d: AttackDefinition, t: float) -> void: ev.telegraph.append([ev.frame, a, d.id if d else &"ult", t])],
		[CombatEvents.kit_event, func(m: Node3D, id: StringName) -> void: ev.kit.append([ev.frame, m, id])],
		[CombatEvents.area_telegraph, func(o: Node3D, p: Vector3, rad: float, t: float, k: StringName) -> void: ev.area.append([ev.frame, o, p, rad, t, k])],
		[CombatEvents.entity_spawned, func(e: Node3D, k: StringName) -> void: ev.spawned.append([ev.frame, e, k])],
		[CombatEvents.entity_removed, func(e: Node3D, k: StringName, d: bool) -> void: ev.removed.append([ev.frame, e, k, d])],
		[CombatEvents.status_changed, func(m: Node3D, id: StringName, n: int) -> void: ev.status.append([ev.frame, m, id, n])],
	]
	for x in c:
		(x[0] as Signal).connect(x[1])
	_conns = c
	return ev


func _unrec() -> void:
	for x in _conns:
		if (x[0] as Signal).is_connected(x[1]):
			(x[0] as Signal).disconnect(x[1])
	_conns = []


func _frames(ev: Dictionary, n: int, each := Callable()) -> void:
	for i in n:
		if each.is_valid():
			each.call(i)
		await r.get_tree().physics_frame
		ev.frame += 1


func _hits(ev: Dictionary, victim: Node, attack_id: StringName = &"") -> Array:
	var out := []
	for h in ev.hits:
		var hi := h[1] as HitInfo
		if hi.victim == victim and (attack_id == &"" or hi.attack.id == attack_id):
			out.append(h)
	return out


func _started(ev: Dictionary, m: Node, id: StringName) -> int:
	var n := 0
	for s in ev.started:
		if s[1] == m and s[2] == id:
			n += 1
	return n


func _kit_events(ev: Dictionary, id: StringName) -> int:
	var n := 0
	for k in ev.kit:
		if k[2] == id:
			n += 1
	return n


func _free(nodes: Array) -> void:
	for n in nodes:
		if n and is_instance_valid(n):
			(n as Node).queue_free()
	for d in r.get_tree().get_nodes_in_group(&"deployables"):
		d.queue_free()
	for p in r.get_tree().get_nodes_in_group(&"projectiles"):
		p.queue_free()
	for o in r.get_tree().get_nodes_in_group(&"orbital_strikes"):
		o.queue_free()
	await r._ticks(3)


## Press a button for one frame (edge) and hold it for `hold` frames.
func _press_skill(m: MechMotor, hold: int) -> Callable:
	return func(i: int) -> void:
		if i == 0:
			m.command.skill_pressed = true
		m.command.skill_held = i < hold
		m.command.attack_pressed = i == hold and _cs(m).is_aiming_placement()  # orbital mark: confirm


func _hover_dummy(pos: Vector3, team := 1, height := 6.0) -> MechMotor:
	var d := MechFactory.create_mech(MechFactory.load_profile(3), team, Color.GRAY, false, load(SERAPH))  # ark profile: longest hover
	d.position = pos
	r.arena.add_child(d)
	await r._ticks(20)
	d.command.jump_pressed = true
	var y0 := d.global_position.y
	for i in 120:
		d.command.ascend = d.global_position.y < y0 + height
		await r.get_tree().physics_frame
	d.command.ascend = false
	await r._ticks(20)
	return d


func all_attacks(p: CombatProfile) -> Array[AttackDefinition]:
	var out: Array[AttackDefinition] = []
	var c := p.light_combo
	while c and not c in out:
		out.append(c)
		c = c.next_attack
	for d in [p.ranged, p.skill, p.skill_hold, p.attack_hold, p.charge_attack, p.defense_action]:
		if d and not d in out:
			out.append(d)
	return out


# ------------------------------------------------------------------ tests

## P01 + P11: every input of every mech does something; configs drive behaviour.
func t28_kits_operable(res: Dictionary) -> void:
	var expect := {
		&"seraph": {"lmb": &"seraph_l1", "x": &"seraph_dash_slash", "f": "PARRY", "rmb": "GUARD"},
		&"hellfang": {"lmb": &"hf_axe1", "x": &"hf_hook", "xh": &"hf_vent", "lmbh": &"hf_ram", "f": "PARRY", "rmb": "GUARD"},
		&"verdant": {"lmb": &"va_scatter", "x": &"va_turret", "xh": &"va_zone", "f": "PARRY", "rmb": "GUARD"},
		&"azure": {"lmb": &"ao_pulse", "x": &"ao_missiles", "xh": &"ao_orbital", "f": &"ao_backstep", "rmb": &"ao_rail"},
	}
	for id: StringName in MechFactory.MECH_IDS:
		var a := _mech(id, 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 20))
		var b := MechFactory.create_by_id(&"seraph", 1, false)
		b.position = Vector3(0, 0.2, 22)
		r.arena.add_child(b)
		await r._ticks(25)
		var e: Dictionary = expect[id]
		var c := _cs(a)
		var got := PackedStringArray()
		for key in ["lmb", "x", "xh", "lmbh", "f", "rmb"]:
			if not e.has(key):
				continue
			c.restore_full()
			a.en = a.profile.max_en
			if id == &"hellfang":
				(c.kit as HeatKit).heat = 70.0 if key == "lmbh" else (50.0 if key == "xh" else 0.0)
			await r._ticks(2)
			var ev := _rec()
			var drive := Callable()
			var frames := 40
			match key:
				"lmb":
					drive = func(i: int) -> void:
						_aim(a, b)
						a.command.attack_pressed = i == 0
						a.command.attack_held = i == 0
				"lmbh":
					drive = func(i: int) -> void:
						_aim(a, b)
						a.command.attack_pressed = i == 0
						a.command.attack_held = i < 30
				"x":
					drive = func(i: int) -> void:
						_aim(a, b)
						a.command.skill_pressed = i == 0
						a.command.skill_held = i < 3
				"xh":
					drive = func(i: int) -> void:
						_aim(a, b)
						a.command.skill_pressed = i == 0
						a.command.skill_held = i < 30
						a.command.attack_pressed = i == 30 and _cs(a).is_aiming_placement()  # round 4: left click confirms the orbital mark
				"f":
					frames = 3
					drive = func(i: int) -> void:
						a.command.parry_pressed = i == 0
				"rmb":
					frames = 70
					drive = func(i: int) -> void:
						_aim(a, b)
						a.command.guard_held = i < 60
			var seen := {"state": ""}
			await _frames(ev, frames, func(i: int) -> void:
				drive.call(i)
				if c.get_state_name() == "GUARD" or c.get_state_name() == "PARRY":
					seen.state = c.get_state_name())
			_unrec()
			a.command.guard_held = false
			a.command.attack_held = false
			a.command.skill_held = false
			var want = e[key]
			var ok := false
			if want is StringName:
				ok = _started(ev, a, want) == 1
			else:
				ok = seen.state == want
			got.append("%s=%s" % [key, want])
			r._check(res, ok, "%s %s → %s" % [id, key.to_upper(), want])
			await r._ticks(45)
		await _free([a, b])
	# --- P11: configuration resources drive behaviour (mutate, test, restore)
	var a2 := _mech(&"verdant", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 10))
	var t2 := MechFactory.create_by_id(&"seraph", 1, false)
	t2.position = Vector3(0, 0.2, 18)
	r.arena.add_child(t2)
	await r._ticks(25)
	var scatter := load("res://resources/combat/verdant/va_scatter.tres") as AttackDefinition
	var old_pellets := scatter.projectile_spec.pellets
	var counts := []
	for n in [old_pellets, 3]:
		scatter.projectile_spec.pellets = n
		var ev2 := _rec()
		var spawned := {"n": 0}
		var before := r.get_tree().get_nodes_in_group(&"projectiles").size()
		await _frames(ev2, 14, func(i: int) -> void:
			_aim(a2, t2)
			a2.command.attack_pressed = i == 0
			spawned.n = maxi(spawned.n, r.get_tree().get_nodes_in_group(&"projectiles").size() - before))
		_unrec()
		counts.append(spawned.n)
		await r._ticks(60)
	scatter.projectile_spec.pellets = old_pellets
	r._check(res, counts[0] == old_pellets and counts[1] == 3, "VERDANT va_scatter.tres pellets %d → 3: projectiles fired %s" % [old_pellets, counts])
	await _free([a2, t2])
	var a3 := _mech(&"azure", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 10))
	await r._ticks(25)
	var bs := load("res://resources/combat/azure/ao_backstep.tres") as AttackDefinition
	var old_cd := bs.cooldown
	bs.cooldown = 2.0
	a3.command.parry_pressed = true
	await r._ticks(3)
	var cd := _cs(a3).get_cooldown(bs.id)
	bs.cooldown = old_cd
	r._check(res, cd > 1.9 and cd <= 2.0, "AZURE ao_backstep.tres cooldown %.0f → 2: runtime cooldown %.2f s" % [old_cd, cd])
	await _free([a3])
	var a4 := _mech(&"hellfang", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 10))
	var t4 := MechFactory.create_by_id(&"seraph", 1, false)
	t4.position = Vector3(0, 0.2, 12)
	r.arena.add_child(t4)
	await r._ticks(25)
	var hook := load("res://resources/combat/hellfang/hf_hook.tres") as AttackDefinition
	var old_range := hook.grapple_spec.max_range
	var outcomes := []
	for rng in [old_range, 10.0]:
		hook.grapple_spec.max_range = rng
		_cs(a4).restore_full()
		r._info("hook range %.0f: start distance %.1f m" % [rng, a4.global_position.distance_to(t4.global_position)])
		var ev4 := _rec()
		await _frames(ev4, 60, func(i: int) -> void:
			_aim(a4, t4)
			a4.command.skill_pressed = i == 0
			a4.command.skill_held = i < 2)
		_unrec()
		outcomes.append("hit" if _hits(ev4, t4, &"hf_hook").size() > 0 else ("miss" if _kit_events(ev4, &"grapple_miss") > 0 else "?"))
		await r._ticks(60)  # let the pull finish
		a4.reset_to(Vector3(0, 0.2, 30))
		await r._ticks(30)
	hook.grapple_spec.max_range = old_range
	r._check(res, outcomes == ["hit", "miss"], "HELLFANG hf_hook.tres max_range %.0f → 10 against an 18 m target: %s" % [old_range, outcomes])
	await _free([a4, t4])
	var a5 := MechFactory.create_by_id(&"hellfang", 0, false)
	a5.position = Vector3(0, 0.2, 30)
	r.arena.add_child(a5)
	await r._ticks(25)
	var heat_cfg := _cs(a5).profile.kit as HeatConfig
	var old_decay := heat_cfg.decay_per_sec
	heat_cfg.decay_per_sec = 40.0
	var hk := _kit(a5) as HeatKit
	hk.add_heat(80.0)
	await r._ticks(60 + 30)
	var after := hk.heat
	heat_cfg.decay_per_sec = old_decay
	r._check(res, absf(after - (80.0 - 40.0 * 0.5)) < 2.0, "HELLFANG heat decay_per_sec %.0f → 40: heat 80 → %.1f after 1.0 s delay + 0.5 s" % [old_decay, after])
	await _free([a5])


## P02: every attack has windup / active / recovery; every skill has a
## cooldown; events come in order; a skill on cooldown cannot restart.
func t29_skill_phases(res: Dictionary) -> void:
	for id: StringName in MechFactory.MECH_IDS:
		var p := load(MechFactory.MECHS[id].combat) as CombatProfile
		var bad := PackedStringArray()
		var skills := [p.skill, p.skill_hold, p.attack_hold, p.charge_attack, p.defense_action]
		for d in all_attacks(p):
			if d.windup <= 0.0 or d.active <= 0.0 or d.recovery <= 0.0:
				bad.append("%s phases %.2f/%.2f/%.2f" % [d.id, d.windup, d.active, d.recovery])
			if d in skills and d.cooldown <= 0.0:
				bad.append("%s no cooldown" % d.id)
		r._check(res, bad.is_empty(), "%s: all %d attacks have windup / active / recovery; skills have cooldowns %s" % [id, all_attacks(p).size(), bad])
	# dynamic: order + cooldown refusal for each mech's X skills
	var cases := [[&"hellfang", &"hf_hook", 3], [&"verdant", &"va_turret", 3], [&"verdant", &"va_zone", 30],
		[&"azure", &"ao_missiles", 3], [&"azure", &"ao_orbital", 30], [&"seraph", &"seraph_dash_slash", 1]]
	for cs in cases:
		var a := _mech(cs[0], 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 10))
		var b := MechFactory.create_by_id(&"seraph", 1, false)
		b.position = Vector3(0, 0.2, 14)
		r.arena.add_child(b)
		await r._ticks(25)
		var ev := _rec()
		var hold: int = cs[2]
		await _frames(ev, 150, func(i: int) -> void:
			_aim(a, b)
			var k := i % 75  # press twice: at 0 (fires) and 75 (on cooldown)
			a.command.skill_pressed = k == 0
			a.command.skill_held = k < hold
			a.command.attack_pressed = k == hold and _cs(a).is_aiming_placement())  # orbital mark: left click confirms
		_unrec()
		var def_id: StringName = cs[1]
		var fs := -1
		var fa := -1
		var ff := -1
		var ft := -1
		for s in ev.started:
			if s[1] == a and s[2] == def_id and fs < 0: fs = s[0]
		for s in ev.active:
			if s[1] == a and s[2] == def_id and fa < 0: fa = s[0]
		for s in ev.finished:
			if s[1] == a and s[2] == def_id and ff < 0: ff = s[0]
		for s in ev.telegraph:
			if s[1] == a and s[2] == def_id and ft < 0: ft = s[0]
		var d := _cs(a).profile.skill if _cs(a).profile.skill.id == def_id else _cs(a).profile.skill_hold
		var order := fs >= 0 and fa > fs and ff > fa and (not d.telegraphed or ft == fs)
		r._check(res, order, "%s %s: start f%d → %stelegraph → active f%d → finished f%d" % [cs[0], def_id, fs, ("" if d.telegraphed else "no "), fa, ff])
		r._check(res, _started(ev, a, def_id) == 1, "%s %s: second press inside the %.0f s cooldown refused (started %d×)" % [cs[0], def_id, d.cooldown, _started(ev, a, def_id)])
		await _free([a, b])


## P03: one damage interface; special attack types vs parry / guard (K14).
func t30_damage_types(res: Dictionary) -> void:
	var att := _mech(&"hellfang", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 26))
	var v := MechFactory.create_by_id(&"seraph", 1, false)
	v.position = Vector3(0, 0.2, 26)
	v.rotation.y = PI  # faces the attacker (+z)
	r.arena.add_child(v)
	await r._ticks(25)
	# type rule uses a non-guard-breaking BEAM; the real orbital (playtest
	# round 2: heavy strike) guard-breaks, checked as its own row
	var plain_beam := (load("res://resources/combat/azure/ao_orbital.tres") as AttackDefinition).duplicate() as AttackDefinition
	plain_beam.guard_break = false
	var defs := {
		"MELEE": load("res://resources/combat/hellfang/hf_axe1.tres"),
		"GRAB": load("res://resources/combat/hellfang/hf_hook.tres"),
		"BEAM": plain_beam,
		"BEAM (heavy orbital)": load("res://resources/combat/azure/ao_orbital.tres"),
		"EXPLOSION": load("res://resources/combat/azure/ao_missile_blast.tres"),
	}
	var expect := {
		"MELEE": [CombatTypes.HitResult.PARRIED, CombatTypes.HitResult.GUARDED],
		"GRAB": [CombatTypes.HitResult.HIT, CombatTypes.HitResult.HIT],
		"BEAM": [CombatTypes.HitResult.HIT, CombatTypes.HitResult.GUARDED],
		"BEAM (heavy orbital)": [CombatTypes.HitResult.HIT, CombatTypes.HitResult.GUARD_BREAK],
		"EXPLOSION": [CombatTypes.HitResult.HIT, CombatTypes.HitResult.GUARDED],
	}
	var vc := _cs(v)
	for k in defs:
		var outs := []
		for mode in ["parry", "guard"]:
			vc.restore_full()
			_cs(att).restore_full()
			v.en = v.profile.max_en
			await r._ticks(2)
			v.command.guard_held = mode == "guard"
			if mode == "parry":
				vc._start_parry()
			else:
				vc._enter_guard()
			await r._ticks(1)
			var h := HitInfo.new()
			h.attacker = att
			h.victim = v
			h.attack = defs[k]
			h.source_position = att.global_position
			h.direction = Vector3(0, 0, -1)
			outs.append(DamageSystem.resolve(h))
			v.command.guard_held = false
			await r._ticks(30)
		r._check(res, outs == expect[k], "%s vs parry / guard → %s / %s (expected %s / %s)" % [k,
			CombatTypes.RESULT_NAMES[outs[0]], CombatTypes.RESULT_NAMES[outs[1]],
			CombatTypes.RESULT_NAMES[expect[k][0]], CombatTypes.RESULT_NAMES[expect[k][1]]])
	# real grapple against a guarding seraph: still grabbed
	vc.restore_full()
	_cs(att).restore_full()
	att.global_position = Vector3(0, 0.2, 40)
	await r._ticks(10)
	var ev := _rec()
	await _frames(ev, 70, func(i: int) -> void:
		_aim(att, v)
		v.command.guard_held = true
		v.command.face_dir = Vector3(0, 0, 1)
		att.command.skill_pressed = i == 0
		att.command.skill_held = i < 2)
	_unrec()
	v.command.guard_held = false
	var gh := _hits(ev, v, &"hf_hook")
	r._check(res, gh.size() == 1 and gh[0][2] == CombatTypes.HitResult.HIT, "real grapple vs guarding SERAPH: %s (grabs ignore guard)" % (CombatTypes.RESULT_NAMES[gh[0][2]] if gh.size() else "no hit"))
	await _free([att, v])
	# single interface: a mixed fight, HP lost == sum of resolved damage (mechs + turret)
	var h1 := _mech(&"hellfang", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 22))
	var g1 := _mech(&"verdant", 1, Vector3(0, 0.2, 22), Vector3(0, 0.2, 30))
	await r._ticks(25)
	var ev2 := _rec()
	await _frames(ev2, 420, func(i: int) -> void:
		_aim(h1, g1)
		_aim(g1, h1)
		if i == 5:
			g1.command.skill_pressed = true
		h1.command.attack_pressed = i % 25 == 0 and i > 60
		g1.command.attack_pressed = i % 30 == 10)
	_unrec()
	var ok := true
	var notes := PackedStringArray()
	for m in [h1, g1]:
		var lost := _cs(m).health.max_hp - _cs(m).health.hp
		var sum := 0.0
		for x in _hits(ev2, m):
			sum += x[3]
		ok = ok and absf(lost - sum) < 0.01
		notes.append("%s lost %.1f / resolved %.1f" % [m.name, lost, sum])
	var types := {}
	for x in ev2.hits:
		types[(x[1] as HitInfo).attack.id] = true
	r._check(res, ok and types.size() >= 3, "every HP change goes through DamageSystem.resolve(): %s; attacks seen %s" % [", ".join(notes), types.keys()])
	await _free([h1, g1])


## P04: statuses — armor break, restraint, marks: apply / stack / expire.
func t31_status_effects(res: Dictionary) -> void:
	var h := _mech(&"hellfang", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 26))
	var v := MechFactory.create_by_id(&"seraph", 1, false)
	v.position = Vector3(0, 0.2, 26.8)
	r.arena.add_child(v)
	await r._ticks(25)
	var ev := _rec()
	# full chain: axe1 → axe2 → finisher (armor break)
	await _frames(ev, 110, func(i: int) -> void:
		_aim(h, v)
		v.global_position = Vector3(0, 0.2, 26.8)
		h.command.attack_pressed = i % 20 == 0 and i < 70)
	_unrec()
	var vc := _cs(v)
	var fin := _hits(ev, v, &"hf_finisher")
	r._check(res, fin.size() == 1 and vc.status.has(&"armor_break"), "finisher landed (%d) → armor break applied (%s, %.1f s left)" % [fin.size(), vc.status.has(&"armor_break"), vc.status.time_left(&"armor_break")])
	(_kit(h) as HeatKit).heat = 0.0
	await r._ticks(40)
	var hp0 := vc.health.hp
	var ab := load("res://resources/combat/status/armor_break.tres") as StatusEffectDefinition
	var ax := load("res://resources/combat/hellfang/hf_axe1.tres") as AttackDefinition
	var ev2 := _rec()
	(_kit(h) as HeatKit).heat = 0.0
	await _frames(ev2, 30, func(i: int) -> void:
		_aim(h, v)
		h.command.attack_pressed = i == 0)
	_unrec()
	var dealt := hp0 - vc.health.hp
	r._check(res, absf(dealt - ax.damage * ab.damage_taken_mult) < 0.05, "armored-broken victim takes ×%.1f: axe %.0f → %.1f" % [ab.damage_taken_mult, ax.damage, dealt])
	await r._ticks(int((ab.duration + 0.2) * 60))
	r._check(res, not vc.status.has(&"armor_break"), "armor break expired after %.0f s" % ab.duration)
	await _free([h, v])
	# restraint zone: slows (never roots) while inside, ends soon after leaving
	var ark := _mech(&"verdant", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 16))
	var run := MechFactory.create_by_id(&"seraph", 1, false)
	run.position = Vector3(-14, 0.2, 16)
	r.arena.add_child(run)
	await r._ticks(25)
	var ev3 := _rec()
	var st := {"in_speed": 99.0, "out_speed": 0.0, "left_at": -1, "cleared_at": -1, "state_ok": true}
	await _frames(ev3, 300, func(i: int) -> void:
		_aim(ark, run)
		if i == 0:
			ark.command.skill_pressed = true
		ark.command.skill_held = i < 30
		ark.command.attack_pressed = i == 30 and _cs(ark).is_aiming_placement()  # round 4: left click confirms the orbital mark
		run.command.move = Vector3(1, 0, 0) if i > 70 else Vector3.ZERO
		var z := _first_zone()
		var sp := run.get_horizontal_velocity().length()
		if z and i > 110:
			if z.contains(run.global_position):
				st.in_speed = minf(st.in_speed, sp) if sp > 0.5 else st.in_speed
			elif st.left_at < 0 and run.global_position.x > z.global_position.x:
				st.left_at = i
		if st.left_at > 0 and i > st.left_at + 50:
			st.out_speed = maxf(st.out_speed, sp)
		if st.left_at > 0 and st.cleared_at < 0 and not _cs(run).status.has(&"restrained"):
			st.cleared_at = i
		if _cs(run).state != CombatStateMachine.CombatState.READY:
			st.state_ok = false)
	_unrec()
	var rs := load("res://resources/combat/status/restrained.tres") as StatusEffectDefinition
	r._check(res, st.in_speed < run.profile.ground_max_speed * rs.speed_mult + 0.6 and st.in_speed > 1.0,
		"inside the zone: speed %.1f m/s ≤ %.0f%% of %.0f (slowed, not rooted)" % [st.in_speed, rs.speed_mult * 100.0, run.profile.ground_max_speed])
	r._check(res, st.cleared_at > 0 and st.cleared_at - st.left_at <= int(rs.duration * 60) + 2 and st.out_speed > run.profile.ground_max_speed * 0.9,
		"left the zone: restraint gone after %d frames, speed back to %.1f m/s" % [st.cleared_at - st.left_at, st.out_speed])
	r._check(res, st.state_ok, "the restraint is a status, never a hard-control state (combat stayed READY)")
	await _free([ark, run])
	# marks: stack to 3, expire
	var az := _mech(&"azure", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 10))
	var tg := MechFactory.create_by_id(&"seraph", 1, false)
	tg.position = Vector3(0, 0.2, 10)
	r.arena.add_child(tg)
	await r._ticks(25)
	var ev4 := _rec()
	var peak := {"n": 0}
	await _frames(ev4, 150, func(i: int) -> void:
		_aim(az, tg)
		az.command.attack_pressed = i % 20 == 0 and i < 120
		peak.n = maxi(peak.n, _cs(tg).status.stacks(&"mark")))
	_unrec()
	var mk := load("res://resources/combat/status/mark.tres") as StatusEffectDefinition
	r._check(res, _hits(ev4, tg, &"ao_pulse").size() >= 5 and peak.n == mk.max_stacks, "%d pulse hits → marks capped at %d" % [_hits(ev4, tg, &"ao_pulse").size(), peak.n])
	await r._ticks(int(mk.duration * 60) + 10)
	r._check(res, _cs(tg).status.stacks(&"mark") == 0, "marks expired %.0f s after the last hit" % mk.duration)
	await _free([az, tg])


func _first_zone() -> SlowZone:
	for d in r.get_tree().get_nodes_in_group(&"deployables"):
		if d is SlowZone:
			return d
	return null


## P05: cover blocks every attack type (walls; roofs for the orbital strike).
func t32_cover(res: Dictionary) -> void:
	# WallThick spans x -20..20 at z = -40 (1 m thick, 12 m tall)
	var behind := Vector3(0, 0.2, -47)
	var front := Vector3(0, 0.2, -30)
	var cases := [[&"verdant", "lmb"], [&"azure", "lmb"], [&"azure", "rail"], [&"azure", "x"], [&"hellfang", "x"]]
	for cs in cases:
		var a := _mech(cs[0], 0, front, behind)
		var v := MechFactory.create_by_id(&"seraph", 1, false)
		v.position = behind
		r.arena.add_child(v)
		await r._ticks(25)
		var ev := _rec()
		var key: String = cs[1]
		await _frames(ev, 200, func(i: int) -> void:
			_aim(a, v)
			if key == "lmb":
				a.command.attack_pressed = i % 30 == 0
			elif key == "rail":
				a.command.guard_held = i < 100
			else:
				a.command.skill_pressed = i == 0
				a.command.skill_held = i < 2)
		_unrec()
		a.command.guard_held = false
		var fired: bool = ev.started.size() > 0
		r._check(res, fired and _hits(ev, v).is_empty() and is_equal_approx(_cs(v).health.hp, _cs(v).health.max_hp),
			"%s %s through WallThick: fired %s, hits on target %d" % [cs[0], key, fired, _hits(ev, v).size()])
		await _free([a, v])
	# turret: no line of sight → never fires at the target behind the wall
	var ark := _mech(&"verdant", 0, front, behind)
	var v2 := MechFactory.create_by_id(&"seraph", 1, false)
	v2.position = behind
	r.arena.add_child(v2)
	await r._ticks(25)
	var ev2 := _rec()
	await _frames(ev2, 300, func(i: int) -> void:
		_aim(ark, v2)
		ark.command.skill_pressed = i == 0)
	_unrec()
	r._check(res, _turrets().size() == 1 and _hits(ev2, v2).is_empty(), "turret 7 m from a target behind WallThick: %d hits in 4 s" % _hits(ev2, v2).size())
	await _free([ark, v2])
	# blast: same distance, with and without the wall in between
	var o := _mech(&"azure", 0, Vector3(30, 0.2, -30))
	var t1 := MechFactory.create_by_id(&"seraph", 1, false)
	t1.position = Vector3(0, 0.2, -41.5)
	r.arena.add_child(t1)
	var t2 := MechFactory.create_by_id(&"seraph", 1, false)
	t2.position = Vector3(10, 0.2, -36.0)
	r.arena.add_child(t2)
	await r._ticks(25)
	var blast := load("res://resources/combat/azure/ao_missile_blast.tres") as AttackDefinition
	var hits_a := AreaBlast.explode(o, blast, Vector3(0, 2.0, -38.8), 3.6)
	var hits_b := AreaBlast.explode(o, blast, Vector3(10, 2.0, -38.8), 3.6)
	r._check(res, hits_a.is_empty() and hits_b.size() == 1, "blast 2.7 m away: behind the wall %d hits, in the open %d hit" % [hits_a.size(), hits_b.size()])
	await _free([o, t1, t2])
	# orbital strike: roofed (SlabLow at 8 m) vs open sky
	var caster := _mech(&"azure", 0, Vector3(-40, 0.2, -20), Vector3(-40, 0.2, -50))
	var under := MechFactory.create_by_id(&"seraph", 1, false)
	under.position = Vector3(-40, 0.2, -50)
	r.arena.add_child(under)
	await r._ticks(25)
	var ev3 := _rec()
	await _frames(ev3, 140, func(i: int) -> void:
		_aim(caster, under)
		caster.command.skill_pressed = i == 0
		caster.command.skill_held = i < 30
		caster.command.attack_pressed = i == 30 and _cs(caster).is_aiming_placement())  # round 4: left click confirms the orbital mark
	_unrec()
	var struck := _kit_events(ev3, &"orbital_strike") > 0
	r._check(res, struck and _hits(ev3, under).is_empty(), "orbital strike on a target under SlabLow: struck %s, hits %d (roof blocks)" % [struck, _hits(ev3, under).size()])
	under.global_position = Vector3(-40, 0.2, -5)
	_cs(caster).restore_full()
	await r._ticks(10)
	var ev4 := _rec()
	await _frames(ev4, 140, func(i: int) -> void:
		_aim(caster, under)
		caster.command.skill_pressed = i == 0
		caster.command.skill_held = i < 30
		caster.command.attack_pressed = i == 30 and _cs(caster).is_aiming_placement())  # round 4: left click confirms the orbital mark
	_unrec()
	r._check(res, _hits(ev4, under, &"ao_orbital").size() == 1, "same strike on the target in the open: %d hit" % _hits(ev4, under, &"ao_orbital").size())
	await _free([caster, under])


func _turrets() -> Array:
	var out := []
	for d in r.get_tree().get_nodes_in_group(&"deployables"):
		if d is Turret and (d as Turret).is_alive():
			out.append(d)
	return out


## P06: heat, deployables, marks and charge.
func t33_resources(res: Dictionary) -> void:
	var h := _mech(&"hellfang", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 26))
	var v := MechFactory.create_by_id(&"seraph", 1, false)
	v.position = Vector3(0, 0.2, 26.8)
	r.arena.add_child(v)
	await r._ticks(25)
	var hk := _kit(h) as HeatKit
	var cfg := hk.cfg()
	var ev := _rec()
	var peak := {"heat": 0.0}
	await _frames(ev, 60, func(i: int) -> void:
		_aim(h, v)
		h.command.attack_pressed = i % 20 == 0
		peak.heat = maxf(peak.heat, hk.heat))
	_unrec()
	r._check(res, peak.heat > 20.0, "axe chain builds heat: peak %.0f" % peak.heat)
	for i in 200:
		if _cs(h).state == CombatStateMachine.CombatState.READY:
			break
		await r.get_tree().physics_frame
	var h_stop := hk.heat
	await r._ticks(int((cfg.decay_delay + 1.0) * 60))
	r._check(res, hk.heat < h_stop - cfg.decay_per_sec * 0.8, "idle cooling after %.1f s: %.0f → %.0f" % [cfg.decay_delay, h_stop, hk.heat])
	# scorching tier
	_cs(v).restore_full()
	_cs(h).restore_full()
	await r._ticks(5)
	hk.heat = cfg.scorch_threshold + 5.0
	var hp0 := _cs(v).health.hp
	await _frames({"frame": 0}, 30, func(i: int) -> void:
		_aim(h, v)
		h.command.attack_pressed = i == 0)
	var ax := load("res://resources/combat/hellfang/hf_axe1.tres") as AttackDefinition
	r._check(res, absf((hp0 - _cs(v).health.hp) - ax.damage * cfg.scorch_damage_mult) < 0.05,
		"scorching (heat ≥ %.0f): axe deals %.1f (= %.0f × %.1f)" % [cfg.scorch_threshold, hp0 - _cs(v).health.hp, ax.damage, cfg.scorch_damage_mult])
	# overheat: forced at max; no attacks, no dashes, more damage taken
	await r._ticks(30)
	hk.heat = cfg.max_heat - 1.0
	h.command.attack_pressed = true
	await r._ticks(4)
	var ov := hk.is_overheated()
	var ev5 := _rec()
	var en0 := h.en
	await _frames(ev5, 30, func(i: int) -> void:
		h.command.attack_pressed = i % 5 == 0
		h.command.dash_pressed = i == 10
		h.command.move = Vector3(1, 0, 0))
	_unrec()
	h.command.move = Vector3.ZERO
	var hi := HitInfo.new()
	hi.attacker = v
	hi.victim = h
	hi.attack = load("res://resources/combat/seraph_l1.tres")
	hi.source_position = v.global_position
	var hp_h := _cs(h).health.hp
	DamageSystem.resolve(hi)
	var taken := hp_h - _cs(h).health.hp
	r._check(res, ov and _started(ev5, h, &"hf_axe1") + _started(ev5, h, &"hf_axe2") == 0 and is_equal_approx(h.en, en0),
		"overheat at %.0f: no attack starts, dash blocked (EN %.0f → %.0f)" % [cfg.max_heat, en0, h.en])
	r._check(res, absf(taken - hi.attack.damage * cfg.overheat_damage_taken) < 0.05, "overheated: takes ×%.1f (%.1f)" % [cfg.overheat_damage_taken, taken])
	await r._ticks(int(cfg.overheat_duration * 60) + 10)
	r._check(res, not hk.is_overheated() and is_equal_approx(hk.heat, cfg.overheat_reset) or (not hk.is_overheated() and hk.heat <= cfg.overheat_reset + 0.01),
		"overheat over after %.1f s, heat reset to %.0f (%.0f)" % [cfg.overheat_duration, cfg.overheat_reset, hk.heat])
	# active vent
	await r._ticks(70)
	hk.heat = 80.0
	var ev6 := _rec()
	await _frames(ev6, 90, _press_skill(h, 30))
	_unrec()
	var vent := load("res://resources/combat/hellfang/hf_vent.tres") as AttackDefinition
	r._check(res, _started(ev6, h, &"hf_vent") == 1 and hk.heat < 80.0 - vent.heat_vent_rate * 0.8 and _kit_events(ev6, &"vent") == 1,
		"X held: active vent, heat 80 → %.0f" % hk.heat)
	# ram whiff → long overheat
	await r._ticks(40)
	_cs(h).restore_full()
	h.global_position = Vector3(30, 0.2, 30)
	await r._ticks(5)
	hk.heat = 70.0
	var ev7 := _rec()
	await _frames(ev7, 200, func(i: int) -> void:
		h.command.face_dir = Vector3(1, 0, 0)
		_cs(h).aim_target = null
		h.command.attack_pressed = i == 0
		h.command.attack_held = i < 30)
	_unrec()
	h.command.attack_held = false
	r._check(res, _started(ev7, h, &"hf_ram") == 1 and _kit_events(ev7, &"overheat") == 1, "whiffed overdrive ram → overheat (%d)" % _kit_events(ev7, &"overheat"))
	await _free([h, v])
	# --- deployables: ≤ 2 turrets, cooldown, lifetime, destroyable
	var ark := _mech(&"verdant", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 10))
	await r._ticks(25)
	var td := load("res://resources/combat/verdant/va_turret.tres") as AttackDefinition
	var ev8 := _rec()
	var counts := []
	for k in 3:
		await _frames(ev8, int((td.cooldown + 0.3) * 60), func(i: int) -> void:
			ark.command.face_dir = Vector3(sin(k * 1.2), 0, -cos(k * 1.2))
			ark.command.skill_pressed = i == 0)
		counts.append(_turrets().size())
	var early := {"n": 0}
	await _frames(ev8, 30, func(i: int) -> void:
		if i == 0:
			ark.command.skill_pressed = true)
	_unrec()
	r._check(res, counts == [1, 2, 2] and _started(ev8, ark, &"va_turret") == 2, "deploy ×3 (each after the %.0f s cooldown): turrets %s — the third is refused" % [td.cooldown, counts])
	var t0 := _turrets()[0] as Turret
	var ev9 := _rec()
	var hit := HitInfo.new()
	var enemy := MechFactory.create_by_id(&"seraph", 1, false)
	enemy.position = Vector3(50, 0.2, 50)
	r.arena.add_child(enemy)
	await r._ticks(5)
	hit.attacker = enemy
	hit.victim = t0
	hit.attack = load("res://resources/combat/seraph_l1.tres")
	hit.damage_mult = 20.0
	hit.source_position = enemy.global_position
	DamageSystem.resolve(hit)
	await r._ticks(3)
	_unrec()
	var destroyed := false
	for e in ev9.removed:
		if e[1] == t0 and e[3]:
			destroyed = true
	r._check(res, destroyed and _turrets().size() == 1, "a turret destroyed by DamageSystem: removed (destroyed) → %d left" % _turrets().size())
	var t_last := _turrets()[0] as Turret
	var left := t_last.time_left()
	await r._ticks(int((left + 0.3) * 60))
	r._check(res, _turrets().is_empty(), "the last turret expired on its own after %.1f s (lifetime %.0f s)" % [left, td.deploy_spec.lifetime])
	await _free([ark, enemy])
	# --- charge scaling + marks
	var az := _mech(&"azure", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 0))
	var tg := MechFactory.create_by_id(&"seraph", 1, false)
	tg.position = Vector3(0, 0.2, 0)
	r.arena.add_child(tg)
	await r._ticks(25)
	var rail := load("res://resources/combat/azure/ao_rail.tres") as AttackDefinition
	var dmg := []
	for frames in [int(_cs(az).profile.charge_time * _cs(az).profile.charge_min * 60) + 2, int(_cs(az).profile.charge_time * 60) + 10]:
		_cs(tg).restore_full()
		_cs(az).restore_full()
		await r._ticks(5)
		var ev10 := _rec()
		await _frames(ev10, frames + 60, func(i: int) -> void:
			_aim(az, tg)
			az.command.guard_held = i < frames)
		_unrec()
		var rh := _hits(ev10, tg, &"ao_rail")
		dmg.append(rh[0][3] if rh.size() else -1.0)
	var spec := rail.projectile_spec
	r._check(res, dmg[0] > 0.0 and absf(dmg[0] - rail.damage) < 1.0 and absf(dmg[1] - rail.damage * spec.charge_damage_mult) < 0.5,
		"railgun: minimum charge %.1f, full charge %.1f (= %.0f × %.2f)" % [dmg[0], dmg[1], rail.damage, spec.charge_damage_mult])
	# full charge breaks a guard; marks add damage and are consumed
	_cs(tg).restore_full()
	_cs(az).restore_full()
	await r._ticks(5)
	var mk := load("res://resources/combat/status/mark.tres") as StatusEffectDefinition
	_cs(tg).status.apply(mk, az, 3)
	var ev11 := _rec()
	var full := int(_cs(az).profile.charge_time * 60) + 10
	await _frames(ev11, full + 60, func(i: int) -> void:
		_aim(az, tg)
		tg.command.face_dir = Vector3(0, 0, 1)
		az.command.guard_held = i < full)
	_unrec()
	var rh2 := _hits(ev11, tg, &"ao_rail")
	r._check(res, rh2.size() == 1 and absf(rh2[0][3] - rail.damage * spec.charge_damage_mult * (1.0 + rail.mark_consume_bonus * 3)) < 0.5
		and _cs(tg).status.stacks(&"mark") == 0,
		"3 marks: full-charge rail %.1f (× %.2f) and marks consumed (%d left)" % [rh2[0][3] if rh2.size() else -1.0, 1.0 + rail.mark_consume_bonus * 3, _cs(tg).status.stacks(&"mark")])
	_cs(tg).restore_full()
	_cs(az).restore_full()
	tg.en = tg.profile.max_en
	await r._ticks(5)
	var ev12 := _rec()
	await _frames(ev12, full + 60, func(i: int) -> void:
		_aim(az, tg)
		tg.command.face_dir = Vector3(0, 0, 1)
		tg.command.guard_held = true
		az.command.guard_held = i < full)
	_unrec()
	tg.command.guard_held = false
	var rh3 := _hits(ev12, tg, &"ao_rail")
	r._check(res, rh3.size() == 1 and rh3[0][2] == CombatTypes.HitResult.GUARD_BREAK, "full-charge rail vs a guard: %s" % (CombatTypes.RESULT_NAMES[rh3[0][2]] if rh3.size() else "no hit"))
	await _free([az, tg])


## P07: every major attack can be read and countered.
func t34_counter_windows(res: Dictionary) -> void:
	# grapple: a sidestep after the telegraph dodges it
	var outs := []
	for dodge in [false, true]:
		var h := _mech(&"hellfang", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 10))
		var v := MechFactory.create_by_id(&"seraph", 1, false)
		v.position = Vector3(0, 0.2, 10)
		r.arena.add_child(v)
		await r._ticks(25)
		var ev := _rec()
		await _frames(ev, 80, func(i: int) -> void:
			if i < 2:
				_aim(h, v)
			h.command.skill_pressed = i == 0
			h.command.skill_held = i < 2
			if dodge and i == 2:
				v.command.dash_pressed = true
			v.command.move = Vector3(1, 0, 0) if dodge else Vector3.ZERO)
		_unrec()
		outs.append(_hits(ev, v, &"hf_hook").size())
		await _free([h, v])
	r._check(res, outs == [1, 0], "grapple at 20 m: standing still → hit %d; side-dash after the telegraph → hit %d" % [outs[0], outs[1]])
	# overdrive ram: side-dash during the 0.6 s windup dodges it
	var outs2 := []
	for dodge in [false, true]:
		var h2 := _mech(&"hellfang", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 16))
		var v2 := MechFactory.create_by_id(&"seraph", 1, false)
		v2.position = Vector3(0, 0.2, 16)
		r.arena.add_child(v2)
		await r._ticks(25)
		(_kit(h2) as HeatKit).heat = 70.0
		var ev2 := _rec()
		await _frames(ev2, 110, func(i: int) -> void:
			_aim(h2, v2)
			h2.command.attack_pressed = i == 0
			h2.command.attack_held = i < 30
			if dodge and i == 30:
				v2.command.dash_pressed = true
			v2.command.move = Vector3(1, 0, 0) if dodge and i >= 28 else Vector3.ZERO)
		_unrec()
		outs2.append(_hits(ev2, v2, &"hf_ram").size())
		await _free([h2, v2])
	r._check(res, outs2 == [1, 0], "ram at 14 m: stand → hit %d; side-dash during the windup → hit %d" % [outs2[0], outs2[1]])
	# railgun: the aiming laser (telegraph) precedes the shot by ≥ the minimum charge
	var az := _mech(&"azure", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 0))
	var tg := MechFactory.create_by_id(&"seraph", 1, false)
	tg.position = Vector3(0, 0.2, 0)
	r.arena.add_child(tg)
	await r._ticks(25)
	var ev3 := _rec()
	await _frames(ev3, 140, func(i: int) -> void:
		_aim(az, tg)
		az.command.guard_held = i < 60)
	_unrec()
	var tf := -1
	var sf := -1
	for t in ev3.telegraph:
		if t[1] == az and t[2] == &"ao_rail": tf = t[0]
	for s in ev3.started:
		if s[1] == az and s[2] == &"ao_rail": sf = s[0]
	var pmin := _cs(az).profile.charge_min * _cs(az).profile.charge_time
	r._check(res, tf >= 0 and sf - tf >= int(pmin * 60), "rail: aiming-laser telegraph at f%d, shot at f%d (≥ %.2f s warning)" % [tf, sf, pmin])
	# missiles: a hard side air-dash dodges most; a pulse can shoot one down
	_cs(az).restore_full()
	tg.global_position = Vector3(0, 0.2, -10)
	await r._ticks(10)
	var ev4 := _rec()
	await _frames(ev4, 200, func(i: int) -> void:
		_aim(az, tg)
		az.command.skill_pressed = i == 0
		az.command.skill_held = i < 2
		tg.command.move = Vector3(1, 0, 0) if i > 25 else Vector3.ZERO
		tg.command.dash_pressed = i == 40 or i == 75)
	_unrec()
	var mhits := _hits(ev4, tg, &"ao_missiles").size()
	r._check(res, mhits <= 2, "4 missiles vs a target dashing sideways at 40 m: %d direct hits (limited homing, not guaranteed)" % mhits)
	await _free([az, tg])
	var a5 := _mech(&"azure", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, -10))
	var b5 := _mech(&"azure", 1, Vector3(0, 0.2, -10), Vector3(0, 0.2, 30))
	await r._ticks(25)
	var ev5 := _rec()
	var sh := {"locked": false}
	await _frames(ev5, 160, func(i: int) -> void:
		_aim(a5, b5)
		a5.command.skill_pressed = i == 0
		a5.command.skill_held = i < 2
		var ms := r.get_tree().get_nodes_in_group(&"projectiles")
		for mm in ms:
			if (mm as Projectile).owner_mech == a5 and (mm as Projectile).health:
				_cs(b5).aim_target = mm
				b5.command.face_dir = Vector3(0, 0, 1)
				sh.locked = true
				break
		b5.command.attack_pressed = sh.locked and i % 13 == 0)
	_unrec()
	var downed := 0
	for e in ev5.removed:
		if e[2] == &"missile" and e[3]:
			downed += 1
	r._check(res, downed >= 1, "a defender's pulse shots down incoming missiles: %d destroyed" % downed)
	await _free([a5, b5])
	# orbital: a side dash once the circle locks (red) dodges it (round 5:
	# faster, wider strike — walking out is no longer enough)
	var outs3 := []
	for dodge in [false, true]:
		var o := _mech(&"azure", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 5))
		var v3 := MechFactory.create_by_id(&"seraph", 1, false)
		v3.position = Vector3(0, 0.2, 5)
		r.arena.add_child(v3)
		await r._ticks(25)
		var ev6 := _rec()
		await _frames(ev6, 160, func(i: int) -> void:
			_aim(o, v3)
			o.command.skill_pressed = i == 0
			o.command.skill_held = i < 30
			o.command.attack_pressed = i == 30 and _cs(o).is_aiming_placement()  # round 4: left click confirms the orbital mark
			var locked := false
			for n in r.get_tree().get_nodes_in_group(&"orbital_strikes"):
				locked = (n as OrbitalStrike).is_locked()
			v3.command.move = Vector3(1, 0, 0) if dodge and locked else Vector3.ZERO
			v3.command.dash_pressed = dodge and locked)
		_unrec()
		var tel := 0.0
		for e in ev6.area:
			if e[5] == &"orbital": tel = e[4]
		outs3.append([_hits(ev6, v3, &"ao_orbital").size(), tel])
		await _free([o, v3])
	r._check(res, outs3[0][0] == 1 and outs3[1][0] == 0 and outs3[0][1] >= 0.7,
		"orbital: %.2f s ground circle; stand → hit %d; side dash once it locks → hit %d" % [outs3[0][1], outs3[0][0], outs3[1][0]])
	# backstep: i-frames are capped, the pulse pushes without damage, long cooldown
	var az2 := _mech(&"azure", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 27))
	var e2 := MechFactory.create_by_id(&"seraph", 1, false)
	e2.position = Vector3(0, 0.2, 27)
	r.arena.add_child(e2)
	await r._ticks(25)
	var bsd := _cs(az2).profile.defense_action
	var ev7 := _rec()
	var hp_e := _cs(e2).health.hp
	var res_t := {}
	var d0 := az2.global_position.distance_to(e2.global_position)
	await _frames(ev7, 40, func(i: int) -> void:
		_aim(az2, e2)
		az2.command.parry_pressed = i == 0
		if i == 6 or i == 26:
			var hh := HitInfo.new()
			hh.attacker = e2
			hh.victim = az2
			hh.attack = load("res://resources/combat/seraph_l1.tres")
			hh.source_position = e2.global_position
			res_t[i] = DamageSystem.resolve(hh))
	_unrec()
	var d1 := az2.global_position.distance_to(e2.global_position)
	r._check(res, res_t.get(6) == CombatTypes.HitResult.EVADED and res_t.get(26) == CombatTypes.HitResult.HIT,
		"backstep: hit at 0.1 s → %s, at 0.43 s → %s (i-frames %.2f s)" % [CombatTypes.RESULT_NAMES[res_t.get(6, 0)], CombatTypes.RESULT_NAMES[res_t.get(26, 0)], bsd.invuln_time])
	r._check(res, d1 > d0 + 4.0 and is_equal_approx(_cs(e2).health.hp, hp_e), "backstep + repulse: separation %.1f → %.1f m, no damage to the pushed mech" % [d0, d1])
	var ev8 := _rec()
	await _frames(ev8, 120, func(i: int) -> void:
		az2.command.parry_pressed = i == 30)
	_unrec()
	r._check(res, _started(ev8, az2, bsd.id) == 0, "second backstep inside the %.0f s cooldown refused" % bsd.cooldown)
	await _free([az2, e2])


## P08: anti-air — every mech reaches a target hovering ~6 m up.
func t35_anti_air(res: Dictionary) -> void:
	# HELLFANG grapple drags an airborne target down (no teleport)
	var h := _mech(&"hellfang", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 14))
	await r._ticks(5)
	var v := await _hover_dummy(Vector3(0, 0.2, 14))
	var y0 := v.global_position.y
	var ev := _rec()
	var st := {"max_step": 0.0, "prev": v.global_position, "min_y": y0}
	await _frames(ev, 70, func(i: int) -> void:
		_aim(h, v)
		v.command.ascend = false
		h.command.skill_pressed = i == 0
		h.command.skill_held = i < 2
		st.max_step = maxf(st.max_step, (v.global_position - (st.prev as Vector3)).length())
		st.prev = v.global_position
		st.min_y = minf(st.min_y, v.global_position.y))
	_unrec()
	var spec := (load("res://resources/combat/hellfang/hf_hook.tres") as AttackDefinition).grapple_spec
	r._check(res, _hits(ev, v, &"hf_hook").size() == 1 and _kit_events(ev, &"grapple_drag") == 1 and y0 - st.min_y > 2.0,
		"HELLFANG grapple on a target hovering %.1f m up: dragged down %.1f m" % [y0 - 0.2, y0 - st.min_y])
	r._check(res, st.max_step <= spec.drag_down_speed * DT * 1.6 + 0.35, "drag is motion, not a teleport: max step %.2f m / frame" % st.max_step)
	await _free([h, v])
	for cs in [[&"verdant", &"va_scatter"], [&"azure", &"ao_pulse"]]:
		var a := _mech(cs[0], 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 18))
		await r._ticks(5)
		var t := await _hover_dummy(Vector3(0, 0.2, 18))
		var ev2 := _rec()
		await _frames(ev2, 90, func(i: int) -> void:
			_aim(a, t)
			a.command.attack_pressed = i % 30 == 0)
		_unrec()
		r._check(res, _hits(ev2, t, cs[1]).size() >= 1, "%s %s reaches a target %.1f m up at 12 m (%d hits)" % [cs[0], cs[1], t.global_position.y, _hits(ev2, t, cs[1]).size()])
		await _free([a, t])


## P09: deployables, missiles, zones, blasts and strikes follow TeamRules.
func t36_team_rules(res: Dictionary) -> void:
	var ark := _mech(&"verdant", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 20))
	var ally := MechFactory.create_by_id(&"seraph", 0, false)
	ally.position = Vector3(-6, 0.2, 20)
	r.arena.add_child(ally)
	var foe := MechFactory.create_by_id(&"seraph", 1, false)
	foe.position = Vector3(6, 0.2, 18)
	r.arena.add_child(foe)
	await r._ticks(25)
	var ev := _rec()
	await _frames(ev, 300, func(i: int) -> void:
		ark.command.face_dir = Vector3(0, 0, -1)
		_cs(ark).aim_target = foe
		ark.command.skill_pressed = i == 0 or i == 420
		if i == 80:
			ark.command.skill_pressed = true
			ark.command.skill_held = true
		ark.command.skill_held = i >= 80 and i < 110)
	_unrec()
	var turret_hits_foe := 0
	for x in _hits(ev, foe):
		if (x[1] as HitInfo).attacker is Turret:
			turret_hits_foe += 1
	r._check(res, turret_hits_foe > 0 and _hits(ev, ally).is_empty(), "turret: %d hits on the enemy, 0 on the ally standing in range" % turret_hits_foe)
	var z := _first_zone()
	r._check(res, z == null or not _cs(ally).status.has(&"restrained"), "restraint zone never affects allies")
	await _free([ark, ally, foe])
	# zone: ally and enemy both inside
	var ark2 := _mech(&"verdant", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 20))
	var al2 := MechFactory.create_by_id(&"seraph", 0, false)
	al2.position = Vector3(1.5, 0.2, 20)
	r.arena.add_child(al2)
	var fo2 := MechFactory.create_by_id(&"seraph", 1, false)
	fo2.position = Vector3(-1.5, 0.2, 20)
	r.arena.add_child(fo2)
	await r._ticks(25)
	var ev2 := _rec()
	await _frames(ev2, 70, func(i: int) -> void:
		_cs(ark2).aim_target = fo2
		ark2.command.face_dir = Vector3(0, 0, -1)
		ark2.command.skill_pressed = i == 0
		ark2.command.skill_held = i < 30
		ark2.command.attack_pressed = i == 30 and _cs(ark2).is_aiming_placement())  # round 4: left click confirms the orbital mark
	_unrec()
	r._check(res, _cs(fo2).status.has(&"restrained") and not _cs(al2).status.has(&"restrained"), "zone over both: enemy restrained %s, ally restrained %s" % [_cs(fo2).status.has(&"restrained"), _cs(al2).status.has(&"restrained")])
	await _free([ark2, al2, fo2])
	# orbital + blast: ally untouched, enemy hit
	var o := _mech(&"azure", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 5))
	var al3 := MechFactory.create_by_id(&"seraph", 0, false)
	al3.position = Vector3(1.5, 0.2, 5)
	r.arena.add_child(al3)
	var fo3 := MechFactory.create_by_id(&"seraph", 1, false)
	fo3.position = Vector3(-1.5, 0.2, 5)
	r.arena.add_child(fo3)
	await r._ticks(25)
	var ev3 := _rec()
	await _frames(ev3, 140, func(i: int) -> void:
		_aim(o, fo3)
		o.command.skill_pressed = i == 0
		o.command.skill_held = i < 30
		o.command.attack_pressed = i == 30 and _cs(o).is_aiming_placement())  # round 4: left click confirms the orbital mark
	_unrec()
	await r._ticks(90)  # round 5: the orbital launches the foe; let it land
	var blast := load("res://resources/combat/azure/ao_missile_blast.tres") as AttackDefinition
	var bl := AreaBlast.explode(o, blast, Vector3(0, 2.0, 5), 3.0)
	var bl_ally := 0
	var bl_foe := 0
	for x in bl:
		if x.victim == al3 and x.result != CombatTypes.HitResult.IGNORED: bl_ally += 1
		if x.victim == fo3 and x.result != CombatTypes.HitResult.IGNORED: bl_foe += 1
	r._check(res, _hits(ev3, fo3, &"ao_orbital").size() == 1 and is_equal_approx(_cs(al3).health.hp, _cs(al3).health.max_hp - 0.0) and bl_ally == 0 and bl_foe == 1,
		"orbital + blast over ally and enemy: enemy hit (orbital %d, blast %d), ally hit 0" % [_hits(ev3, fo3, &"ao_orbital").size(), bl_foe])
	await _free([o, al3, fo3])
	# missiles fly through an ally in the way
	var m := _mech(&"azure", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 0))
	var al4 := MechFactory.create_by_id(&"seraph", 0, false)
	al4.position = Vector3(0, 0.2, 20)
	r.arena.add_child(al4)
	var fo4 := MechFactory.create_by_id(&"seraph", 1, false)
	fo4.position = Vector3(0, 0.2, 0)
	r.arena.add_child(fo4)
	await r._ticks(25)
	var ev4 := _rec()
	await _frames(ev4, 160, func(i: int) -> void:
		_aim(m, fo4)
		m.command.skill_pressed = i == 0
		m.command.skill_held = i < 2)
	_unrec()
	r._check(res, _hits(ev4, al4).is_empty() and _hits(ev4, fo4).size() >= 1, "missiles pass the ally in the way (%d hits) and reach the enemy (%d)" % [_hits(ev4, al4).size(), _hits(ev4, fo4).size()])
	await _free([m, al4, fo4])
	# FFA: a turret shoots any hostile, three teams
	var ark5 := _mech(&"verdant", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 20))
	var x1 := MechFactory.create_by_id(&"seraph", 1, false)
	x1.position = Vector3(-8, 0.2, 24)
	r.arena.add_child(x1)
	var x2 := MechFactory.create_by_id(&"seraph", 2, false)
	x2.position = Vector3(8, 0.2, 18)
	r.arena.add_child(x2)
	await r._ticks(25)
	var ev5 := _rec()
	await _frames(ev5, 360, func(i: int) -> void:
		ark5.command.face_dir = Vector3(0, 0, -1)
		ark5.command.skill_pressed = i == 0
		if i == 200:
			x1.global_position = Vector3(-80, 0.2, 80)  # first target leaves: the turret retargets
	)
	_unrec()
	var by_t := {x1: 0, x2: 0}
	for x in ev5.hits:
		var hi := x[1] as HitInfo
		if hi.attacker is Turret and by_t.has(hi.victim) and x[2] != CombatTypes.HitResult.IGNORED:
			by_t[hi.victim] += 1
	r._check(res, by_t[x1] > 0 and by_t[x2] > 0, "FFA: the turret hits both hostile teams (team 1: %d, team 2: %d)" % [by_t[x1], by_t[x2]])
	await _free([ark5, x1, x2])


# ------------------------------------------------------------------ T37 playtest round 1

## Fixes from the 2026-11-19 playtest: grapple stagger covers the pull and
## interrupts; PALE SERAPH 反刺; EN costs / regen / idle regen; orbital circle
## follows then locks; dash gait does not speed up the walk cycle.
func t37_playtest_fixes(res: Dictionary) -> void:
	# --- 1. grapple: target interrupted, still staggered when HELLFANG arrives
	var hf := _mech(&"hellfang", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 10))
	var az := _mech(&"azure", 1, Vector3(0, 0.2, 10), Vector3(0, 0.2, 30))
	await r._ticks(25)
	var st := {"charging_before": false, "grab_f": -1, "after_grab_charging": true, "arrive_state": "", "arrive_d": 0.0}
	var ev := _rec()
	await _frames(ev, 150, func(i: int) -> void:
		_aim(hf, az)
		az.command.guard_held = st.grab_f < 0  # AZURE keeps charging the rail until grabbed
		if i == 30:
			st.charging_before = _cs(az).is_charging()
		hf.command.skill_pressed = i == 30
		if st.grab_f < 0 and _kit_events(ev, &"grapple_pull") > 0:
			st.grab_f = i
			st.after_grab_charging = _cs(az).is_charging()
		var d := Vector2(az.global_position.x - hf.global_position.x, az.global_position.z - hf.global_position.z).length()
		if st.grab_f >= 0 and st.arrive_state == "" and d <= 4.0:
			st.arrive_state = _cs(az).get_state_name()
			st.arrive_d = d)
	_unrec()
	r._check(res, st.charging_before and st.grab_f >= 0 and not st.after_grab_charging,
		"grapple hit interrupts a charging rail (charging before %s, after grab %s)" % [st.charging_before, st.after_grab_charging])
	r._check(res, st.arrive_state == "STAGGER", "target still STAGGER when HELLFANG arrives (%.1f m: %s)" % [st.arrive_d, st.arrive_state])
	await _free([hf, az])

	# --- 2. 反刺: attack inside the window → riposte, unguardable, ×counter
	var cp := load(SERAPH) as CombatProfile
	var rip := cp.parry_riposte
	r._check(res, rip != null and not rip.guardable and not rip.parryable, "PALE SERAPH profile carries an unguardable riposte (%s)" % (rip.id if rip else &"none"))
	for pid in [&"hellfang", &"verdant"]:
		var pp := load(String((MechFactory.MECHS[pid] as Dictionary).combat)) as CombatProfile
		r._check(res, pp.parry_riposte == null and not pp.parry_causes_offbalance, "%s parry: push-back only, no riposte" % pid)
	for late in [false, true]:
		var a := _mech(&"seraph", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 26.5))
		var b := _mech(&"seraph", 1, Vector3(0, 0.2, 26.5), Vector3(0, 0.2, 30))
		await r._ticks(20)
		var ev2 := _rec()
		var s2 := {"open": false, "press": -1}
		await _frames(ev2, 110, func(i: int) -> void:
			_aim(a, b)
			_aim(b, a)
			a.command.attack_pressed = i == 10
			b.command.parry_pressed = i == 13
			if not s2.open and _cs(b).riposte_target == a:
				s2.open = true
				s2.press = i + 2 if not late else i + 70
			a.command.guard_held = s2.press >= 0 and i >= s2.press
			b.command.attack_pressed = i == s2.press)
		_unrec()
		var hb := _hits(ev2, a)
		var first: HitInfo = (hb[0][1] as HitInfo) if hb.size() > 0 else null
		if not late:
			r._check(res, s2.open and first != null and first.attack.id == rip.id and first.result == CombatTypes.HitResult.HIT \
					and is_equal_approx(first.final_damage, rip.damage * cp.counter_damage_mult),
				"parry → attack inside the window: %s %.1f dmg, guard ignored" % [first.attack.id if first else &"-", first.final_damage if first else 0.0])
		else:
			r._check(res, first != null and first.attack.id == cp.light_combo.id,
				"attack after the window closed: normal %s (not a riposte)" % [first.attack.id if first else &"-"])
		await _free([a, b])

	# --- 3. EN: costs from resources, regen delay, idle regen ×2
	var m := _mech(&"seraph", 0, Vector3(0, 0.2, 30))
	await r._ticks(20)
	var pr := m.profile
	r._check(res, is_equal_approx(pr.ground_dash_cost, 16.0) and is_equal_approx(pr.ground_regen_per_sec, 32.0) and is_equal_approx(pr.regen_delay, 0.5) and is_equal_approx(pr.idle_regen_mult, 2.0),
		"EN defaults: ground dash %.0f, regen %.0f/s, delay %.1f s, idle ×%.1f" % [pr.ground_dash_cost, pr.ground_regen_per_sec, pr.regen_delay, pr.idle_regen_mult])
	var rates := []
	for moving in [false, true]:
		m.en = 20.0
		m.consume_en(0.0)
		m.command.move = Vector3.ZERO
		await r._ticks(40)  # past the regen delay
		var e0 := m.en
		var ev3 := _rec()
		await _frames(ev3, 30, func(_i: int) -> void:
			m.command.move = Vector3(1, 0, 0) if moving else Vector3.ZERO)
		_unrec()
		rates.append((m.en - e0) / 0.5)
		m.command.move = Vector3.ZERO
		await r._ticks(30)
	r._check(res, rates[0] > rates[1] * 1.8 and rates[1] > 0.0, "standing still regenerates %.0f EN/s vs %.0f EN/s while walking" % [rates[0], rates[1]])
	await _free([m])

	# --- 4. orbital: follows then locks; marks lengthen the follow
	var spec := (load("res://resources/combat/azure/ao_orbital.tres") as AttackDefinition).orbital_spec
	var o := _mech(&"azure", 0, Vector3(0, 0.2, 40), Vector3(0, 0.2, 10))
	var v := _mech(&"seraph", 1, Vector3(0, 0.2, 10))
	await r._ticks(25)
	var s4 := {"strike": null, "p_call": Vector3.ZERO, "p_lock": Vector3.ZERO, "p_end": Vector3.ZERO, "locked_moved": 0.0}
	var ev4 := _rec()
	await _frames(ev4, 150, func(i: int) -> void:
		_aim(o, v)
		o.command.skill_pressed = i == 0
		o.command.skill_held = i < 30
		o.command.attack_pressed = i == 30 and _cs(o).is_aiming_placement()  # round 4: left click confirms the orbital mark
		v.command.move = Vector3(1, 0, 0) if s4.strike != null else Vector3.ZERO  # strafe from the moment it appears
		v.command.dash_pressed = s4.strike != null and is_instance_valid(s4.strike) and (s4.strike as OrbitalStrike).is_locked()  # round 5: dash once it locks
		if s4.strike == null:
			for n in r.get_tree().get_nodes_in_group(&"orbital_strikes"):
				s4.strike = n
				s4.p_call = (n as Node3D).global_position
		elif is_instance_valid(s4.strike):
			var sn := s4.strike as OrbitalStrike
			if not sn.is_locked():
				s4.p_lock = sn.global_position
			else:
				s4.locked_moved = maxf(s4.locked_moved, sn.global_position.distance_to(s4.p_lock)))
	_unrec()
	var followed := Vector2(s4.p_lock.x - s4.p_call.x, s4.p_lock.z - s4.p_call.z).length()
	r._check(res, followed > 1.5 and s4.locked_moved < 0.05,
		"circle followed the strafing target %.1f m, then stayed put after locking (moved %.2f m)" % [followed, s4.locked_moved])
	r._check(res, _hits(ev4, v, &"ao_orbital").is_empty(), "a target that dashes out once it locks escapes (%d hits)" % _hits(ev4, v, &"ao_orbital").size())
	var tel := 0.0
	for e in ev4.area:
		if e[5] == &"orbital": tel = e[4]
	r._check(res, is_equal_approx(tel, spec.follow_time + spec.lock_time), "unmarked telegraph %.2f s = follow %.1f + lock %.1f" % [tel, spec.follow_time, spec.lock_time])
	await _free([o, v])
	var o2 := _mech(&"azure", 0, Vector3(0, 0.2, 40), Vector3(0, 0.2, 10))
	var v2 := _mech(&"seraph", 1, Vector3(0, 0.2, 10))
	await r._ticks(25)
	var mark := load("res://resources/combat/status/mark.tres") as StatusEffectDefinition
	_cs(v2).status.apply(mark, o2, 3)
	_aim(o2, v2)
	var strike := OrbitalStrike.call_strike(_cs(o2), load("res://resources/combat/azure/ao_orbital.tres"))
	r._check(res, is_equal_approx(strike.follow_duration, spec.follow_time + 3 * spec.follow_per_mark),
		"3 marks: follow %.2f s (lock window unchanged %.1f s)" % [strike.follow_duration, spec.lock_time])
	strike.queue_free()
	await _free([o2, v2])

	# --- 5. dash gait: the walk cycle does not speed up during a ground dash
	var g := MechFactory.create_by_id(&"seraph", 0, true)
	g.position = Vector3(0, 0.2, 30)
	r.arena.add_child(g)
	await r._ticks(20)
	var vis: Node = null
	for c in g.get_children():
		if c is MechVisual:
			vis = c
	var ph := []
	for dash in [false, true]:
		var ev5 := _rec()
		var p0: float = vis.get(&"_walk_phase")
		await _frames(ev5, 12, func(i: int) -> void:
			g.command.move = Vector3(1, 0, 0)
			g.command.dash_pressed = dash and i == 0)
		_unrec()
		ph.append(float(vis.get(&"_walk_phase")) - p0)
		g.command.move = Vector3.ZERO
		await r._ticks(40)
	r._check(res, ph[1] <= ph[0] * 1.05 + 0.01, "walk-cycle advance over 0.2 s: walking %.2f rad, dashing %.2f rad (no faster)" % [ph[0], ph[1]])
	await _free([g])


# ------------------------------------------------------------------ playtest round 2

func t38_playtest_round2(res: Dictionary) -> void:
	# --- 1. 反刺 window opens even when the attacker is immune to hard control
	var cp := load(SERAPH) as CombatProfile
	var a := _mech(&"seraph", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 26.5))
	var b := _mech(&"seraph", 1, Vector3(0, 0.2, 26.5), Vector3(0, 0.2, 30))
	await r._ticks(20)
	for k in 4:
		_cs(a).cc_duration(0.1)  # three recent hard controls → the 4th makes it immune
	r._check(res, _cs(a).cc_immune_left > 0.0, "attacker made CC-immune (%.1f s)" % _cs(a).cc_immune_left)
	var ev := _rec()
	var s1 := {"open": false, "press": -1, "left": 0.0, "att_state": ""}
	await _frames(ev, 90, func(i: int) -> void:
		_aim(a, b)
		_aim(b, a)
		a.command.attack_pressed = i == 10
		b.command.parry_pressed = i == 13
		if not s1.open and _cs(b).riposte_target == a:
			s1.open = true
			s1.left = _cs(b).riposte_left
			s1.att_state = _cs(a).get_state_name()
			s1.press = i + 20  # ≈ 0.33 s later: past the old (decayed) window
		b.command.attack_pressed = i == s1.press)
	_unrec()
	var hb := _hits(ev, a)
	var first: HitInfo = (hb[0][1] as HitInfo) if hb.size() > 0 else null
	r._check(res, s1.open and s1.att_state != "OFFBALANCE" and is_equal_approx(s1.left, cp.riposte_window),
		"window opens without off-balance (attacker %s), length %.2f s" % [s1.att_state, s1.left])
	r._check(res, first != null and first.attack.id == cp.parry_riposte.id and is_equal_approx(first.final_damage, cp.parry_riposte.damage * cp.counter_damage_mult),
		"riposte 0.33 s after the parry: %s %.1f dmg" % [first.attack.id if first else &"-", first.final_damage if first else 0.0])
	await _free([a, b])

	# --- 2. Q acquires the nearest, most threatening unit (not just the view)
	var p := _mech(&"seraph", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 0))
	var near := _mech(&"verdant", 1, Vector3(8, 0.2, 30))
	var far := _mech(&"azure", 2, Vector3(0, 0.2, 10))
	for x in [p, near, far]:
		x.add_to_group(&"lock_targets")
	var ts := TargetingSystem.new()
	r.arena.add_child(ts)
	ts.setup(p, null)
	await r._ticks(5)
	var pick0 := ts.acquire()
	ts._set_target(null, "test")
	_cs(far).aim_target = p
	var h := HitInfo.new()
	h.attacker = far
	h.victim = p
	h.attack = load("res://resources/combat/azure/ao_pulse.tres")
	h.source_position = far.global_position
	h.direction = Vector3(0, 0, 1)
	DamageSystem.resolve(h)
	await r._ticks(2)
	var pick1 := ts.acquire()
	r._check(res, pick0 == near and pick1 == far,
		"acquire: idle units → nearest (%s); a unit aiming at and hitting us 20 m away → %s (threat %.0f m)" % [
			pick0.name if pick0 else "none", pick1.name if pick1 else "none", ts.threat_of(far)])
	ts.queue_free()
	await _free([p, near, far])

	# --- 3. judgment: 10 s, ×1.25, shockwave, light-hit super armour, suppression field
	var s := _mech(&"seraph", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 24))
	var e := _mech(&"hellfang", 1, Vector3(0, 0.2, 24), Vector3(0, 0.2, 30))
	var fe := _mech(&"verdant", 1, Vector3(30, 0.2, 30))
	await r._ticks(20)
	var u := _cs(s).ultimate
	u.enter_judgment()
	r._check(res, is_equal_approx(u.phase_time_left, 10.0) and is_equal_approx(u.outgoing_mult(), 1.25), "judgment %.0f s, damage ×%.2f" % [u.phase_time_left, u.outgoing_mult()])
	await r._ticks(5)
	e.en = 50.0
	var en0 := e.en
	await r._ticks(60)
	r._check(res, _cs(e).status.has(&"judgment_suppressed") and not _cs(fe).status.has(&"judgment_suppressed") and e.en <= en0 + 0.01,
		"field: enemy at 6 m suppressed (EN %.0f → %.0f, no regen), enemy at 30 m not" % [en0, e.en])
	var ev3 := _rec()
	await _frames(ev3, 80, func(i: int) -> void:
		_aim(s, e)
		_aim(e, s)
		s.command.attack_pressed = i == 62  # after the axe (a lance hit would interrupt it)
		if i == 60:
			e.reset_to(Vector3(0, 0.2, 24))  # round 5: the axe steps in (and bites); back to 6 m once it is over
		e.command.attack_pressed = i == 2)
	_unrec()
	var waves := _hits(ev3, e, &"seraph_judgment_wave")
	var wdef := u.definition.wave_attack
	r._check(res, waves.size() == 1 and is_equal_approx((waves[0][1] as HitInfo).final_damage, wdef.damage * 1.25),
		"lance strike releases a shockwave: %d hit, %.2f dmg" % [waves.size(), (waves[0][1] as HitInfo).final_damage if waves.size() > 0 else 0.0])
	var e_start := -1
	var e_active := -1
	for x in ev3.started:
		if x[1] == e and e_start < 0: e_start = x[0]
	for x in ev3.active:
		if x[1] == e and e_active < 0: e_active = x[0]
	var axe := (load("res://resources/combat/hellfang/hf_axe1.tres") as AttackDefinition)
	r._check(res, e_start >= 0 and e_active - e_start >= int(axe.windup * 60.0 * 1.2),
		"suppressed windup: %d frames (base %.0f)" % [e_active - e_start, axe.windup * 60.0])
	await r._ticks(40)
	var sc := _cs(s)
	var states := []
	for def_path in ["res://resources/combat/hellfang/hf_axe1.tres", "res://resources/combat/hellfang/hf_finisher.tres"]:
		await r._ticks(30)
		var hh := HitInfo.new()
		hh.attacker = e
		hh.victim = s
		hh.attack = load(def_path)
		hh.source_position = e.global_position
		hh.direction = Vector3(0, 0, 1)
		DamageSystem.resolve(hh)
		states.append(sc.get_state_name())
	r._check(res, states[0] != "STAGGER" and states[1] == "STAGGER",
		"super armour: 15-dmg axe → %s; 26-dmg finisher → %s" % [states[0], states[1]])
	await _free([s, e, fe])

	# --- 4. heavy orbital: full damage, launch, then the circle burns (round 5: 50 + launch, 2 s burn)
	var o := _mech(&"azure", 0, Vector3(0, 0.2, 40), Vector3(0, 0.2, 10))
	var v := _mech(&"seraph", 1, Vector3(0, 0.2, 10))
	await r._ticks(25)
	var ev4 := _rec()
	var odef4 := load("res://resources/combat/azure/ao_orbital.tres") as AttackDefinition
	var hmax := {"y": 0.0}
	await _frames(ev4, 330, func(i: int) -> void:
		_aim(o, v)
		o.command.skill_pressed = i == 0
		o.command.skill_held = i < 30
		o.command.attack_pressed = i == 30 and _cs(o).is_aiming_placement()  # round 4: left click confirms the orbital mark
		hmax.y = maxf(hmax.y, v.global_position.y))
	_unrec()
	var oh := _hits(ev4, v, &"ao_orbital")
	var burns := _hits(ev4, v, &"ao_orbital_burn")
	r._check(res, oh.size() == 1 and is_equal_approx((oh[0][1] as HitInfo).final_damage, odef4.damage) and burns.size() >= 1 and hmax.y > 4.0,
		"orbital %.0f dmg, target launched %.1f m up, then %d burn ticks" % [(oh[0][1] as HitInfo).final_damage if oh.size() > 0 else 0.0, hmax.y, burns.size()])
	await _free([o, v])

	# --- 5. HELLFANG 熔炉格挡: absorbed damage vents as a blast on release
	var cfg := (load("res://resources/combat/hellfang_combat.tres") as CombatProfile).kit as HeatConfig
	for big in [true, false]:
		var hf := _mech(&"hellfang", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 26))
		var en := _mech(&"seraph", 1, Vector3(0, 0.2, 26), Vector3(0, 0.2, 30))
		var fr := _mech(&"seraph", 1, Vector3(0, 0.2, 14), Vector3(0, 0.2, 30))
		await r._ticks(20)
		var ev5 := _rec()
		var hit_def: AttackDefinition = load("res://resources/combat/hellfang/hf_axe1.tres") if big else load("res://resources/combat/azure/ao_pulse.tres")
		await _frames(ev5, 90, func(i: int) -> void:
			_aim(hf, en)
			hf.command.guard_held = i < 40
			if i == 10 or (big and i == 20):
				var g := HitInfo.new()
				g.attacker = en
				g.victim = hf
				g.attack = hit_def
				g.source_position = en.global_position
				g.direction = Vector3(0, 0, 1)
				DamageSystem.resolve(g))
		_unrec()
		var bursts := _hits(ev5, en, &"hf_furnace_burst")
		if big:
			var want := cfg.furnace_burst.damage + 2.0 * hit_def.damage * cfg.furnace_damage_per_absorbed
			r._check(res, _kit_events(ev5, &"furnace_burst") == 1 and bursts.size() == 1 \
					and absf((bursts[0][1] as HitInfo).final_damage - want) < 0.01 and _hits(ev5, fr, &"hf_furnace_burst").is_empty(),
				"guard absorbed %.0f → release: blast %.0f dmg (want %.0f) at 4 m, none at 16 m" % [2.0 * hit_def.damage,
					(bursts[0][1] as HitInfo).final_damage if bursts.size() > 0 else 0.0, want])
		else:
			r._check(res, _kit_events(ev5, &"furnace_burst") == 0, "guard absorbed only %.0f (< %.0f): no blast" % [hit_def.damage, cfg.furnace_min_absorbed])
		await _free([hf, en, fr])

	# --- 6. VERDANT 盾墙: blocks hostile shots, breaks, then cools down
	var va := _mech(&"verdant", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 10))
	var az := _mech(&"azure", 1, Vector3(0, 0.2, 10), Vector3(0, 0.2, 30))
	await r._ticks(20)
	var dcfg := _kit(va).config as DeployConfig
	var ev6 := _rec()
	await _frames(ev6, 130, func(i: int) -> void:
		_aim(va, az)
		_aim(az, va)
		va.command.guard_held = i < 3
		az.command.attack_pressed = i > 20 and i % 20 == 0)
	_unrec()
	var walls := r.get_tree().get_nodes_in_group(&"shield_walls")
	var w: ShieldWall = walls[0] if walls.size() > 0 else null
	r._check(res, w != null and _kit_events(ev6, &"wall_up") == 1 and absf(w.global_position.z - (30.0 - dcfg.wall_distance)) < 0.6,
		"guard raises one wall %.1f m ahead" % (30.0 - w.global_position.z if w else 0.0))
	r._check(res, w != null and w.health.hp < dcfg.wall_hp and _hits(ev6, va).is_empty(),
		"hostile pulses hit the wall (HP %.0f / %.0f), none reach the ark" % [w.health.hp if w else 0.0, dcfg.wall_hp])
	if w:
		w.health.take(10000.0)
	await r._ticks(3)
	var ev7 := _rec()
	await _frames(ev7, 10, func(i: int) -> void:
		va.command.guard_held = i < 5)
	_unrec()
	r._check(res, r.get_tree().get_nodes_in_group(&"shield_walls").is_empty() and _kit_events(ev7, &"wall_up") == 0 \
			and (_kit(va) as DeployKit).wall_cooldown_left > dcfg.wall_cooldown - 0.5,
		"broken wall → %.1f s cooldown, guard raises nothing meanwhile" % (_kit(va) as DeployKit).wall_cooldown_left)
	await _free([va, az])


func t39_experiments(res: Dictionary) -> void:
	r._check(res, not Experiments.momentum and not Experiments.duel_cam and not Experiments.free_aim, "experiments default OFF outside the skill lab")
	# --- 速度即伤害
	Experiments.momentum = true
	r._check(res, is_equal_approx(Experiments.momentum_mult(5.0), 1.0) and is_equal_approx(Experiments.momentum_mult(20.0), 1.3) \
			and is_equal_approx(Experiments.momentum_mult(200.0), 1.0 + Experiments.MOMENTUM_MAX_BONUS),
		"closing speed bonus: 5 m/s ×%.2f, 20 m/s ×%.2f, cap ×%.2f" % [Experiments.momentum_mult(5.0), Experiments.momentum_mult(20.0), Experiments.momentum_mult(200.0)])
	var a := _mech(&"seraph", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 26.5))
	var b := _mech(&"hellfang", 1, Vector3(0, 0.2, 26.5), Vector3(0, 0.2, 30))
	await r._ticks(20)
	_cs(b).health.setup(100000.0)
	var ev := _rec()
	var st := {"first_f": -1, "cancel_f": -1, "press2": -1}
	await _frames(ev, 90, func(i: int) -> void:
		_aim(a, b)
		a.command.attack_pressed = i == 2 or i == st.press2
		if st.first_f < 0 and not _hits(ev, b).is_empty():
			st.first_f = i
		a.command.dash_pressed = st.first_f >= 0 and st.cancel_f < 0
		a.command.move = Vector3(0, 0, -1) if a.command.dash_pressed else Vector3.ZERO
		if st.cancel_f < 0 and _kit_events(ev, &"dash_cancel") > 0:
			st.cancel_f = i
			st.press2 = i + 6)
	_unrec()
	var hb := _hits(ev, b)
	var d1: float = (hb[0][1] as HitInfo).final_damage if hb.size() > 0 else 0.0
	var d2: float = (hb[1][1] as HitInfo).final_damage if hb.size() > 1 else 0.0
	r._check(res, st.cancel_f >= 0 and st.cancel_f - st.first_f <= 12, "landed hit dash-cancelled %d frames later (chain %d)" % [st.cancel_f - st.first_f, _cs(a).momentum_chain])
	r._check(res, hb.size() >= 2 and d2 >= d1 * (1.0 + Experiments.CHAIN_STEP) - 0.01, "chained attack hits harder: %.1f → %.1f (chain ×%.1f)" % [d1, d2, 1.0 + Experiments.CHAIN_STEP])
	await _free([a, b])
	# dash attack: start the swing at dash speed → it slides in and hits harder
	var dmg := []
	for dash in [false, true]:
		var a2 := _mech(&"seraph", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 18))
		var b2 := _mech(&"hellfang", 1, Vector3(0, 0.2, 18), Vector3(0, 0.2, 30))
		await r._ticks(20)
		_cs(b2).health.setup(100000.0)
		var ev2 := _rec()
		var st2 := {"pressed": false}
		await _frames(ev2, 70, func(i: int) -> void:
			_aim(a2, b2)
			var dist := a2.global_position.distance_to(b2.global_position)
			a2.command.move = Vector3(0, 0, -1) if not st2.pressed else Vector3.ZERO
			a2.command.dash_pressed = dash and i == 0
			if not st2.pressed and dist < 7.5:
				st2.pressed = true
				a2.command.attack_pressed = true)
		_unrec()
		var hh := _hits(ev2, b2)
		dmg.append([(hh[0][1] as HitInfo).final_damage if hh.size() > 0 else 0.0, (hh[0][1] as HitInfo).momentum_mult if hh.size() > 0 else 0.0])
		await _free([a2, b2])
	r._check(res, dmg[0][0] > 0.0 and dmg[1][1] >= 1.3 and dmg[1][0] > dmg[0][0] * 1.25,
		"swing from a walk %.1f dmg (×%.2f); from a dash %.1f dmg (×%.2f)" % [dmg[0][0], dmg[0][1], dmg[1][0], dmg[1][1]])
	Experiments.momentum = false

	# --- 自由瞄准: ranged fire goes to the crosshair point, or to the assist target
	Experiments.free_aim = true
	var az := _mech(&"azure", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 10))
	var t := _mech(&"seraph", 1, Vector3(0, 0.2, 10))
	await r._ticks(20)
	var c := _cs(az)
	var dirs := []
	for assist in [false, true]:
		c.free_aim_active = true
		c.free_aim_point = Vector3(20, 2.6, 10)
		c.free_aim_target = t if assist else null
		var ev2 := _rec()
		var probe := {"dir": Vector3.ZERO}
		await _frames(ev2, 12, func(i: int) -> void:
			_aim(az, t)
			az.command.attack_pressed = i == 0
			for n in r.get_tree().get_nodes_in_group(&"projectiles"):
				if probe.dir == Vector3.ZERO and (n as Projectile).owner_mech == az:
					probe.dir = (n as Projectile).velocity.normalized())
		_unrec()
		var muzzle := az.global_position + Vector3.UP * 2.6
		var want := ((t.global_position + Vector3.UP * 2.0) if assist else c.free_aim_point) - muzzle
		dirs.append(rad_to_deg(probe.dir.angle_to(want.normalized())) if probe.dir != Vector3.ZERO else 180.0)
		await _free([])
	r._check(res, dirs[0] < 3.0 and dirs[1] < 6.0, "shot toward the crosshair point (off %.1f°), toward the assist target (off %.1f°)" % [dirs[0], dirs[1]])
	c.free_aim_active = false
	Experiments.free_aim = false
	await _free([az, t])

	# --- 近战俯瞰镜头 (round 4; replaced the round-2 side swing)
	var m := MechFactory.create_by_id(&"seraph", 0, false)
	m.position = Vector3(0, 0.2, 30)
	r.arena.add_child(m)
	var tg := _mech(&"verdant", 1, Vector3(0, 0.2, 22))
	tg.add_to_group(&"lock_targets")
	var tsys := TargetingSystem.new()
	m.add_child(tsys)
	var rig := CameraRig.new()
	r.arena.add_child(rig)
	tsys.setup(m, rig.camera)
	rig.setup(m, tsys)
	tsys._set_target(tg, "test")
	var ang := []
	for duel in [false, true]:
		Experiments.duel_cam = duel
		await r._ticks(150)
		var fwd := -rig.camera.global_basis.z
		var line := tg.global_position - m.global_position
		ang.append(rad_to_deg(Vector2(fwd.x, fwd.z).angle_to(Vector2(line.x, line.z))))
	Experiments.duel_cam = false
	r._check(res, rig.overview_blend() > 0.99 and absf(ang[1]) < 45.0,
		"locked at 8 m: the round-4 overview camera is on (view vs target line %.0f° normally, %.0f° overview)" % [absf(ang[0]), absf(ang[1])])
	rig.queue_free()
	await _free([m, tg])


func t40_playtest_round3(res: Dictionary) -> void:
	var odef := load("res://resources/combat/azure/ao_orbital.tres") as AttackDefinition
	var spec := odef.orbital_spec
	# --- 1a. hand-marked empty ground: the circle stays exactly there, full warning
	var az := _mech(&"azure", 0, Vector3(0, 0.2, 40), Vector3(0, 0.2, 10))
	var v := _mech(&"seraph", 1, Vector3(0, 0.2, 10))
	await r._ticks(25)
	var c := _cs(az)
	var mark := Vector3(14, 0.0, 10)
	var st := {"aim": false, "aim_after_release": false, "strike": null, "found": false, "p0": Vector3.ZERO, "moved": 0.0, "tel": 0.0, "fixed": false}
	var ev := _rec()
	await _frames(ev, 170, func(i: int) -> void:
		_aim(az, v)
		az.command.skill_pressed = i == 0
		az.command.skill_held = i < 25  # round 4: X may be released, the mark stays
		az.command.attack_pressed = i == 40
		if c.is_aiming_placement():
			st.aim = true
			if i == 35:
				st.aim_after_release = true
			c.placement_point = mark
			c.placement_set = true
		v.command.move = Vector3(0, 0, -1) if i > 60 and i < 90 else Vector3.ZERO
		if st.strike == null:
			for n in r.get_tree().get_nodes_in_group(&"orbital_strikes"):
				st.strike = n
				st.found = true
				st.p0 = (n as Node3D).global_position
				st.tel = (n as OrbitalStrike).telegraph
				st.fixed = (n as OrbitalStrike).fixed_point
		elif is_instance_valid(st.strike):
			st.moved = maxf(st.moved, (st.strike as Node3D).global_position.distance_to(st.p0)))
	_unrec()
	r._check(res, st.aim and st.found and st.fixed and st.aim_after_release and Vector2(st.p0.x - mark.x, st.p0.z - mark.z).length() < 0.6 and st.moved < 0.05,
		"X held → AIM, still marking after X is released; left click → strike on the marked ground (%.1f m off), fixed (moved %.2f m)" % [Vector2(st.p0.x - mark.x, st.p0.z - mark.z).length(), st.moved])
	r._check(res, is_equal_approx(st.tel, spec.follow_time + spec.lock_time) and _hits(ev, v, &"ao_orbital").is_empty(),
		"fixed mark keeps the full %.1f s warning; the target 14 m away is not hit" % st.tel)
	await _free([az, v])
	# --- 1b. marked on an enemy: it follows that enemy
	var az2 := _mech(&"azure", 0, Vector3(0, 0.2, 40), Vector3(0, 0.2, 10))
	var v2 := _mech(&"seraph", 1, Vector3(0, 0.2, 10))
	await r._ticks(25)
	var c2 := _cs(az2)
	c2.placement_point = v2.global_position + Vector3(3, 0, 0)
	c2.placement_set = true
	var strike := OrbitalStrike.call_strike(c2, odef)
	r._check(res, strike.target == v2 and not strike.fixed_point and not c2.placement_set,
		"mark 3 m from an enemy → follows it (target %s), mark consumed" % (strike.target.name if strike.target else "none"))
	strike.queue_free()
	# --- 1c. guard cancels the aim: nothing spent
	var en0 := az2.en
	var ev2 := _rec()
	await _frames(ev2, 50, func(i: int) -> void:
		_aim(az2, v2)
		az2.command.skill_pressed = i == 0
		az2.command.skill_held = i < 45
		az2.command.guard_held = i >= 30 and i < 33)
	_unrec()
	r._check(res, _started(ev2, az2, &"ao_orbital") == 0 and c2.get_cooldown(&"ao_orbital") <= 0.0 and az2.en >= en0 - 0.01 and not c2.is_aiming_placement(),
		"right button during AIM cancels: no strike, no cooldown, EN %.0f → %.0f" % [en0, az2.en])
	await _free([az2, v2])

	# --- 2. skill lab: camera rises, ghost follows the view ray; F9 syncs the ranged partner
	var sc := (load("res://scenes/test/skill_lab.tscn") as PackedScene).instantiate()
	sc.process_mode = Node.PROCESS_MODE_PAUSABLE
	r.add_child(sc)
	await r._ticks(10)
	sc.call(&"swap_player", &"azure")
	await r._ticks(3)
	var brain := sc.get("brain") as PlayerBrain
	brain.enabled = false
	var player := sc.get("motor") as MechMotor
	var rig := sc.get("rig") as CameraRig
	var pc := _cs(player)
	var dummies: Array = sc.get("dummies")
	(sc.get("targeting") as TargetingSystem)._set_target(dummies[0], "test")
	var h0 := rig.camera.global_position.y - player.global_position.y
	var st2 := {"h": 0.0}
	var ev3 := _rec()
	await _frames(ev3, 50, func(i: int) -> void:
		player.command.skill_pressed = i == 0
		player.command.skill_held = true
		brain.update_placement_aim(pc)
		st2.h = rig.camera.global_position.y - player.global_position.y)
	_unrec()
	var ret: PlacementReticle = brain.get(&"_reticle")
	var reach := Vector2(pc.placement_point.x - player.global_position.x, pc.placement_point.z - player.global_position.z).length()
	var d_lock := Vector2(pc.placement_point.x - (dummies[0] as Node3D).global_position.x, pc.placement_point.z - (dummies[0] as Node3D).global_position.z).length()
	var tl := (dummies[0] as Node3D).global_position - player.global_position
	r._check(res, d_lock < spec.radius, "the marker starts on the locked target %.0f m away (%.1f m off, circle r %.0f)" % [Vector2(tl.x, tl.z).length(), d_lock, spec.radius])
	r._check(res, pc.is_aiming_placement() and rig.placement_mode and pc.placement_set and ret != null and ret.visible and reach <= spec.max_call_range + 0.1,
		"AIM: raised view on, ghost shown %.1f m ahead (≤ %.0f m)" % [reach, spec.max_call_range])
	r._check(res, st2.h > h0 + 5.0, "camera height above the mech %.1f → %.1f m" % [h0, st2.h])
	await _frames(ev3, 6, func(i: int) -> void:
		player.command.skill_held = false
		player.command.attack_pressed = i == 0  # left click confirms
		brain.update_placement_aim(pc))
	r._check(res, pc.state == CombatStateMachine.CombatState.ATTACK and pc.attack and pc.attack.id == &"ao_orbital" and not rig.placement_mode and not ret.visible,
		"left click → orbital fires, view and ghost back to normal (%s)" % pc.get_state_name())
	var mb := (dummies[0] as Node).get_node(^"SparringBrain") as SparringBrain
	var rb := (dummies[1] as Node).get_node(^"SparringBrain") as SparringBrain
	var pairs := []
	var ok := true
	for k in 5:
		var e := InputEventAction.new()
		e.action = &"debug_dummy_mode"
		e.pressed = true
		sc.call(&"_unhandled_input", e)
		pairs.append("%s/%s" % [mb.get_mode_name(), rb.get_mode_name()])
		var want: int = {SparringBrain.Mode.TRAINING: SparringBrain.Mode.TRAINING_RANGED, SparringBrain.Mode.MELEE: SparringBrain.Mode.RANGED}.get(mb.mode, mb.mode)
		ok = ok and rb.mode == want
	r._check(res, ok, "F9 cycles both partners: %s" % ", ".join(pairs))
	sc.queue_free()
	await r._ticks(3)
	r._check(res, not Experiments.momentum and not Experiments.duel_cam and not Experiments.free_aim and is_equal_approx(Engine.time_scale, 1.0),
		"leaving the skill lab switches the experiments off again")

	# (parry presentation: see T41 — round 4 replaced the frontal disc with the outward sweep)


func t41_playtest_round4(res: Dictionary) -> void:
	# --- 1. close-combat overview: a target circling you at 5 m barely turns the view
	var m := MechFactory.create_by_id(&"seraph", 0, false)
	m.position = Vector3(0, 0.2, 30)
	r.arena.add_child(m)
	var tg := _mech(&"verdant", 1, Vector3(0, 0.2, 25))
	for x in [m, tg]:
		x.add_to_group(&"lock_targets")
	var tsys := TargetingSystem.new()
	m.add_child(tsys)
	var rig := CameraRig.new()
	r.arena.add_child(rig)
	tsys.setup(m, rig.camera)
	rig.setup(m, tsys)
	tsys._set_target(tg, "test")
	var turned := {}
	var framed := {}
	for ov in [false, true]:
		Experiments.duel_cam = ov
		await r._ticks(60)
		var st := {"total": 0.0, "prev": Vector3.ZERO, "inview": true, "th": 0.0}
		var ev := _rec()
		await _frames(ev, 120, func(i: int) -> void:
			st.th += 4.0 / 60.0
			var c := m.global_position
			tg.global_position = Vector3(c.x + sin(st.th) * 5.0, tg.global_position.y, c.z - cos(st.th) * 5.0)
			var f := -rig.camera.global_basis.z
			f.y = 0.0
			if st.prev != Vector3.ZERO:
				st.total += rad_to_deg(st.prev.angle_to(f))
			st.prev = f
			if i > 10:
				for n in [m, tg]:
					if not rig.camera.is_position_in_frustum((n as Node3D).global_position + Vector3.UP * 2.0):
						st.inview = false)
		_unrec()
		turned[ov] = st.total
		framed[ov] = st.inview
	r._check(res, turned[true] < 120.0 and turned[false] > 250.0,
		"target circling at 5 m for 2 s: view turned %.0f° with the overview, %.0f° with the old lock camera" % [turned[true], turned[false]])
	r._check(res, framed[true] and rig.overview_blend() > 0.99, "overview keeps you and the target on screen the whole time")
	# a third mech aiming at you 15 m away joins the frame
	var third := _mech(&"azure", 2, Vector3(15, 0.2, 30))
	third.add_to_group(&"lock_targets")
	_cs(third).aim_target = m
	tg.global_position = Vector3(0, tg.global_position.y, 25)
	await r._ticks(90)
	var members := rig.overview_members()
	var dist := rig.camera.global_position.distance_to(rig.get(&"_ov_focus"))
	r._check(res, members.has(third) and rig.camera.is_position_in_frustum(third.global_position + Vector3.UP * 2.0) and dist <= rig.overview_max_dist + 0.5,
		"a threat 15 m away is framed too (%d mechs, arm %.1f m ≤ %.0f)" % [members.size(), dist, rig.overview_max_dist])
	# cinematic cuts: at most one per 1.5 s
	var fb := CombatFeedback.new()
	r.arena.add_child(fb)
	fb.rig = rig
	fb.focus_mech = m
	var l1 := load("res://resources/combat/seraph_l1.tres") as AttackDefinition
	for k in 2:
		_cs(m)._start_parry()
		await r._ticks(1)
		var h := HitInfo.new()
		h.attacker = tg
		h.victim = m
		h.attack = l1
		h.source_position = tg.global_position
		h.direction = Vector3(0, 0, 1)
		DamageSystem.resolve(h)
		await r._ticks(30)
	r._check(res, fb.cinematic_count == 1, "two parries 0.5 s apart → %d cinematic cut (cooldown 1.5 s)" % fb.cinematic_count)
	fb.queue_free()
	Engine.time_scale = 1.0
	Experiments.duel_cam = false
	rig.queue_free()
	await _free([m, tg, third])

	# --- 2. orbital marking is a toggle and survives hard control
	var az := _mech(&"azure", 0, Vector3(0, 0.2, 40), Vector3(0, 0.2, 10))
	var v := _mech(&"seraph", 1, Vector3(0, 0.2, 10))
	await r._ticks(25)
	var c := _cs(az)
	var mark := Vector3(6, 0.0, 12)
	var pulse := load("res://resources/combat/sparring_pulse_shot.tres") as AttackDefinition
	var s2 := {"released_aim": false, "stag_pending": false, "resumed": false, "kept": false}
	var ev2 := _rec()
	await _frames(ev2, 130, func(i: int) -> void:
		_aim(az, v)
		az.command.skill_pressed = i == 0
		az.command.skill_held = i < 25
		if i == 30:
			s2.released_aim = c.is_aiming_placement()
			c.placement_point = mark
			c.placement_set = true
		if i == 40:
			var h := HitInfo.new()
			h.attacker = v
			h.victim = az
			h.attack = pulse
			h.source_position = v.global_position
			h.direction = Vector3(0, 0, 1)
			DamageSystem.resolve(h)
		if i == 44:
			s2.stag_pending = c.get_state_name() == "STAGGER" and c.aim_pending()
		if i == 90:
			s2.resumed = c.is_aiming_placement()
			s2.kept = c.placement_set and c.placement_point.distance_to(mark) < 0.01
		az.command.attack_pressed = i == 95)
	_unrec()
	r._check(res, s2.released_aim, "X released after entering the mark: still marking")
	r._check(res, s2.stag_pending and s2.resumed and s2.kept,
		"0.2 s stagger pauses the mark (pending %s), then it resumes (%s) with the same point (%s)" % [s2.stag_pending, s2.resumed, s2.kept])
	r._check(res, _started(ev2, az, &"ao_orbital") == 1, "left click fires the marked strike")
	await _free([az, v])
	var az2 := _mech(&"azure", 0, Vector3(0, 0.2, 40), Vector3(0, 0.2, 10))
	var v2 := _mech(&"seraph", 1, Vector3(0, 0.2, 10))
	await r._ticks(25)
	var c2 := _cs(az2)
	var en0 := az2.en
	var ev3 := _rec()
	await _frames(ev3, int((c2.profile.aim_timeout + 0.8) * 60.0), func(i: int) -> void:
		_aim(az2, v2)
		az2.command.skill_pressed = i == 0
		az2.command.skill_held = i < 25)
	_unrec()
	r._check(res, not c2.aim_pending() and _kit_events(ev3, &"aim_timeout") == 1 and _started(ev3, az2, &"ao_orbital") == 0 \
			and c2.get_cooldown(&"ao_orbital") <= 0.0 and az2.en >= en0 - 0.01,
		"untouched mark cancels itself after %.0f s: no strike, no cooldown, EN %.0f → %.0f" % [c2.profile.aim_timeout, en0, az2.en])
	await _free([az2, v2])

	# --- 3. parry: wide outward sweep of the shield arm, edge ribbon, judgment halo
	var g := MechFactory.create_by_id(&"seraph", 0, true)
	g.position = Vector3(0, 0.2, 30)
	r.arena.add_child(g)
	await r._ticks(20)
	var gc := _cs(g)
	var vis: MechVisual = null
	for ch in g.get_children():
		if ch is MechVisual:
			vis = ch
	var arm := vis.get(&"_arm_l") as Node3D
	var tip := vis.get(&"_shield_tip") as Node3D
	var trail := vis.get(&"_shield_trail") as WeaponTrail
	var s3 := {"ly_min": 0.0, "ly_end": 0.0, "arc": 0.0, "prev": Vector3.ZERO, "samples": 0}
	gc._start_parry()
	var ev4 := _rec()
	await _frames(ev4, 9, func(_i: int) -> void:
		s3.ly_min = minf(s3.ly_min, arm.rotation.y)
		s3.ly_end = arm.rotation.y
		if s3.prev != Vector3.ZERO:
			s3.arc += (s3.prev as Vector3).distance_to(tip.global_position)
		s3.prev = tip.global_position
		s3.samples = maxi(s3.samples, trail.sample_count()))
	_unrec()
	r._check(res, s3.ly_min < -0.6 and s3.ly_end > 1.0 and s3.arc > 2.5 and s3.samples >= 3,
		"0.15 s: shield arm coils (ly %.2f) and sweeps out (ly %.2f), shield edge travels %.1f m, ribbon %d samples" % [s3.ly_min, s3.ly_end, s3.arc, s3.samples])
	await r._ticks(40)
	gc.ultimate.enter_judgment()
	gc._start_parry()
	await r._ticks(15)
	var fx := vis.get_node_or_null(^"ParryFx")
	r._check(res, fx != null and trail.color.r > 0.9 and trail.color.b < 0.5 and trail.life > 0.25,
		"judgment parry: golden ribbon (life %.2f s) and the energy-shield halo at the end of the sweep (%s)" % [trail.life, "yes" if fx else "no"])
	await _free([g])


func t42_playtest_round5(res: Dictionary) -> void:
	# --- 1. AZURE orbital: fast, wide, launches, outer shockwave
	var odef := load("res://resources/combat/azure/ao_orbital.tres") as AttackDefinition
	var spec := odef.orbital_spec
	r._check(res, is_equal_approx(odef.windup + spec.follow_time + spec.lock_time, 0.95) and is_equal_approx(odef.cooldown, 5.0) \
			and is_equal_approx(spec.radius, 7.0) and spec.shock_attack != null,
		"orbital data: confirm → impact %.2f s, cooldown %.0f s, radius %.0f m, shockwave to %.0f m" % [odef.windup + spec.follow_time + spec.lock_time, odef.cooldown, spec.radius, spec.shock_radius])
	var o := _mech(&"azure", 0, Vector3(0, 0.2, 40), Vector3(0, 0.2, 10))
	var v := _mech(&"seraph", 1, Vector3(0, 0.2, 10))
	var side := _mech(&"seraph", 1, Vector3(9, 0.2, 10))
	await r._ticks(25)
	var st := {"confirm": -1, "impact": -1, "vy": 0.0, "side0": side.global_position}
	var ev := _rec()
	await _frames(ev, 150, func(i: int) -> void:
		_aim(o, v)
		o.command.skill_pressed = i == 0
		o.command.skill_held = i < 25
		var c := _cs(o)
		if c.is_aiming_placement() and st.confirm < 0 and i >= 25:
			c.placement_point = v.global_position
			c.placement_set = true
			o.command.attack_pressed = true
			st.confirm = i
		if st.impact < 0 and _kit_events(ev, &"orbital_strike") > 0:
			st.impact = i
		st.vy = maxf(st.vy, v.global_position.y))
	_unrec()
	var dt: float = (st.impact - st.confirm) / 60.0
	var sh := _hits(ev, side, &"ao_orbital_shock")
	var s0: Vector3 = st.side0
	var pushed := Vector2(side.global_position.x - s0.x, side.global_position.z - s0.z).length()
	r._check(res, st.confirm >= 0 and st.impact > st.confirm and dt < 1.05, "left click → impact in %.2f s (was 1.55 s)" % dt)
	r._check(res, _hits(ev, v, &"ao_orbital").size() == 1 and st.vy > 4.0, "target in the circle launched %.1f m up" % st.vy)
	r._check(res, sh.size() == 1 and _hits(ev, side, &"ao_orbital").is_empty() and pushed > 1.0,
		"mech 9 m away: shockwave %d hit (%.0f dmg), pushed %.1f m outward" % [sh.size(), (sh[0][1] as HitInfo).final_damage if sh.size() > 0 else 0.0, pushed])
	await _free([o, v, side])

	# --- 2. HELLFANG step-in swings and the bite
	var hf := _mech(&"hellfang", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 24))
	var tg := _mech(&"seraph", 1, Vector3(0, 0.2, 24.3))  # 5.7 m: beyond the old 4.4 m reach
	await r._ticks(20)
	_cs(tg).health.setup(100000.0)
	var z0 := hf.global_position.z
	var s2 := {"step1": 0.0, "z_hit": 0.0}
	var ev2 := _rec()
	await _frames(ev2, 40, func(i: int) -> void:
		_aim(hf, tg)
		hf.command.attack_pressed = i == 0)
	_unrec()
	var first := _hits(ev2, tg)
	s2.step1 = z0 - hf.global_position.z
	var step1: float = s2.step1
	r._check(res, first.size() >= 1 and _cs(tg).status.has(&"bitten") and step1 > 1.0,
		"axe steps in %.1f m and hits a target 5.7 m away (%d hit), target bitten %s" % [step1, first.size(), _cs(tg).status.has(&"bitten")])
	# bitten: the next swing lunges much farther
	tg.reset_to(Vector3(0, 0.2, hf.global_position.z - 7.5))
	await r._ticks(2)
	var hk := _kit(hf) as HeatKit
	var z1 := hf.global_position.z
	var ev3 := _rec()
	await _frames(ev3, 40, func(i: int) -> void:
		_aim(hf, tg)
		hf.command.attack_pressed = i == 0)
	_unrec()
	var step2 := z1 - hf.global_position.z
	var axe := load("res://resources/combat/hellfang/hf_axe1.tres") as AttackDefinition
	var plain := axe.lunge_speed * axe.lunge_duration
	r._check(res, step2 > plain * 2.0 and _hits(ev3, tg).size() >= 1,
		"bitten target 7.5 m away: the swing lunges %.1f m (plain lunge %.1f m) and connects" % [step2, plain])
	# bitten: a dash swerves onto the target
	tg.reset_to(Vector3(8, 0.2, hf.global_position.z - 8))
	await r._ticks(30)
	_cs(tg).status.apply(hk.cfg().bite_status, hf)
	hk._bite(tg)
	var p0 := hf.global_position
	await _frames(ev3, 6, func(i: int) -> void:
		hf.command.move = Vector3(0, 0, -1)  # input 45° off the target
		hf.command.dash_pressed = i == 0)
	var mv := hf.global_position - p0
	var to_t := tg.global_position - p0
	var off := rad_to_deg(Vector2(mv.x, mv.z).angle_to(Vector2(to_t.x, to_t.z)))
	r._check(res, absf(off) < 8.0, "dash 45° off a bitten target swerves onto it (%.1f° off)" % absf(off))
	await _free([hf, tg])

	# --- 3. HELLFANG grapple: a claw on a chain; misses cool down faster; walls are latched
	var hook := load("res://resources/combat/hellfang/hf_hook.tres") as AttackDefinition
	r._check(res, is_equal_approx(hook.grapple_spec.speed, 85.0) and is_equal_approx(hook.grapple_spec.radius, 0.9),
		"hook data: speed %.0f m/s, radius %.1f m" % [hook.grapple_spec.speed, hook.grapple_spec.radius])
	var g := MechFactory.create_by_id(&"hellfang", 0, true)
	g.position = Vector3(0, 0.2, -22)
	g.rotation.y = 0.0  # facing -z: WallThick is 18 m ahead
	r.arena.add_child(g)
	await r._ticks(20)
	var gc := _cs(g)
	gc.aim_target = null
	var s3 := {"links": 0, "prongs_hidden": false}
	var vis: MechVisual = null
	for ch in g.get_children():
		if ch is MechVisual:
			vis = ch
	var gz0 := g.global_position.z
	var ev4 := _rec()
	await _frames(ev4, 70, func(i: int) -> void:
		g.command.face_dir = Vector3(0, 0, -1)
		g.command.skill_pressed = i == 0
		for c in r.arena.get_children():
			if c is Grapple:
				var ch := (c as Grapple).get(&"_chain") as MultiMeshInstance3D
				s3.links = maxi(s3.links, ch.multimesh.visible_instance_count)
				var pr: Array = vis.get(&"_claw_prongs")
				s3.prongs_hidden = s3.prongs_hidden or (pr.size() > 0 and not (pr[0] as Node3D).visible))
	_unrec()
	var moved := gz0 - g.global_position.z
	r._check(res, _kit_events(ev4, &"grapple_wall") == 1 and moved > 8.0 and ev4.hits.is_empty() and gc.get_cooldown(&"hf_hook") <= hook.grapple_spec.miss_cooldown + 0.01,
		"hook hits WallThick: latched, pulled %.1f m toward it, no damage, cooldown %.1f s" % [moved, gc.get_cooldown(&"hf_hook")])
	r._check(res, s3.links >= 10 and s3.prongs_hidden, "chain drawn (%d links) and the arm claw is out while the hook flies" % s3.links)
	await _free([g])
	var a := _mech(&"hellfang", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 10))
	var b := _mech(&"seraph", 1, Vector3(0, 0.2, 14))
	var c4 := _mech(&"seraph", 1, Vector3(30, 0.2, 30))
	await r._ticks(20)
	var cds := []
	for hit_it in [false, true]:
		_cs(a)._cooldowns.clear()
		await _frames(ev4, 60, func(i: int) -> void:
			_aim(a, b)
			if not hit_it:
				a.command.face_dir = Vector3(1, 0, 0)  # throw into the open: miss
				_cs(a).aim_target = null
			a.command.skill_pressed = i == 0)
		cds.append(_cs(a).get_cooldown(&"hf_hook"))
		a.reset_to(Vector3(0, 0.2, 30))
		b.reset_to(Vector3(0, 0.2, 14))
		await r._ticks(70)
	r._check(res, cds[0] <= hook.grapple_spec.miss_cooldown and cds[0] > 0.0 and cds[1] > hook.grapple_spec.miss_cooldown,
		"cooldown after a miss %.1f s (≤ %.1f), after a grab %.1f s (full %.0f s)" % [cds[0], hook.grapple_spec.miss_cooldown, cds[1], hook.cooldown])
	await _free([a, b, c4])

	# --- 4. overheat: shorter, dash allowed, steam pushes enemies away
	var cfg := (load("res://resources/combat/hellfang_combat.tres") as CombatProfile).kit as HeatConfig
	var h := _mech(&"hellfang", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 26))
	var e := _mech(&"seraph", 1, Vector3(0, 0.2, 27))
	await r._ticks(20)
	var e0 := e.global_position
	var hp0 := _cs(e).health.hp
	(_kit(h) as HeatKit).add_heat(200.0)
	var s5 := {"dashed": false}
	var ev5 := _rec()
	await _frames(ev5, 20, func(i: int) -> void:
		h.command.move = Vector3(1, 0, 0)
		h.command.dash_pressed = i == 5
		if h.state == MechMotor.MotionState.GROUND_DASH:
			s5.dashed = true)
	_unrec()
	var pushed2 := e.global_position.distance_to(e0)
	r._check(res, is_equal_approx(cfg.overheat_duration, 1.0) and is_equal_approx(cfg.overheat_damage_taken, 1.15) and s5.dashed \
			and pushed2 > 2.0 and is_equal_approx(_cs(e).health.hp, hp0),
		"overheat %.1f s, damage taken ×%.2f, can dash (%s); steam pushed the enemy %.1f m, no damage" % [cfg.overheat_duration, cfg.overheat_damage_taken, s5.dashed, pushed2])
	await _free([h, e])


## Round-5 regressions found by diagnosis (scripted duels: HELLFANG weaker).
func t43_round5_regressions(res: Dictionary) -> void:
	# 1. point-blank grapple: the hook starts inside / past an adjacent target
	for gap in [2.0, 3.0, 4.5]:
		var hf := _mech(&"hellfang", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 20))
		var tg := _mech(&"seraph", 1, Vector3(0, 0.2, 30.0 - gap))
		await r._ticks(20)
		var ev := _rec()
		await _frames(ev, 40, func(i: int) -> void:
			_aim(hf, tg)
			hf.command.skill_pressed = i == 0)
		_unrec()
		r._check(res, _hits(ev, tg, &"hf_hook").size() == 1 and _kit_events(ev, &"grapple_miss") == 0,
			"hook at point blank (%.1f m): grabbed %d, misses %d" % [gap, _hits(ev, tg, &"hf_hook").size(), _kit_events(ev, &"grapple_miss")])
		await _free([hf, tg])
	# 2. rhythmic presses (every 0.32 s, the sparring cadence) still reach the finisher
	var a := _mech(&"hellfang", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 20))
	var b := _mech(&"seraph", 1, Vector3(0, 0.2, 27))
	await r._ticks(20)
	_cs(b).health.setup(100000.0)
	var ev2 := _rec()
	await _frames(ev2, 90, func(i: int) -> void:
		_aim(a, b)
		a.command.attack_pressed = i == 0 or i == 19 or i == 38)
	_unrec()
	r._check(res, _started(ev2, a, &"hf_finisher") == 1,
		"presses every 0.32 s: axe → cleave → finisher (finisher started %d×)" % _started(ev2, a, &"hf_finisher"))
	var p := (load("res://resources/combat/hellfang_combat.tres") as CombatProfile)
	var d := p.light_combo
	var ok := true
	while d:
		ok = ok and d.lunge_duration <= d.active + 0.001
		d = d.next_attack
	r._check(res, ok, "combo lunges fit inside the active window (the chain point does not move)")
	await _free([a, b])
