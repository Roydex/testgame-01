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
			a.command.skill_held = k < hold)
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
	var defs := {
		"MELEE": load("res://resources/combat/hellfang/hf_axe1.tres"),
		"GRAB": load("res://resources/combat/hellfang/hf_hook.tres"),
		"BEAM": load("res://resources/combat/azure/ao_orbital.tres"),
		"EXPLOSION": load("res://resources/combat/azure/ao_missile_blast.tres"),
	}
	var expect := {
		"MELEE": [CombatTypes.HitResult.PARRIED, CombatTypes.HitResult.GUARDED],
		"GRAB": [CombatTypes.HitResult.HIT, CombatTypes.HitResult.HIT],
		"BEAM": [CombatTypes.HitResult.HIT, CombatTypes.HitResult.GUARDED],
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
		caster.command.skill_held = i < 30)
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
		caster.command.skill_held = i < 30)
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
	# orbital: walking out of the circle during the telegraph dodges it
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
			v3.command.move = Vector3(1, 0, 0) if dodge and ev6.area.size() > 0 else Vector3.ZERO)
		_unrec()
		var tel := 0.0
		for e in ev6.area:
			if e[5] == &"orbital": tel = e[4]
		outs3.append([_hits(ev6, v3, &"ao_orbital").size(), tel])
		await _free([o, v3])
	r._check(res, outs3[0][0] == 1 and outs3[1][0] == 0 and outs3[0][1] >= 1.0,
		"orbital: %.1f s ground circle; stand → hit %d; walk out → hit %d" % [outs3[0][1], outs3[0][0], outs3[1][0]])
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
		ark2.command.skill_held = i < 30)
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
		o.command.skill_held = i < 30)
	_unrec()
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
