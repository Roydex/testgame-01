extends "res://tests/phase3_tests.gd"
## Round 6 (2026-11-20, user design): defences per mech, moves, ultimates,
## global tempo. Reuses the phase-3 helpers (_mech, _rec, _frames …).
## NOTE: lambdas capture locals by value — mutable probe state lives in
## Dictionaries.

const L1 := "res://resources/combat/seraph_l1.tres"
const ORBITAL := "res://resources/combat/azure/ao_orbital.tres"
const PULSE := "res://resources/combat/azure/ao_pulse.tres"


func _shoot(owner: Node3D, def: AttackDefinition, from: Vector3, at: Vector3) -> Projectile:
	var p := Projectile.new()
	r.arena.add_child(p)
	p.global_position = from
	p.launch(owner, def, (at - from).normalized() * def.projectile_speed)
	return p


## Hits on `victim` whose attacker is `attacker` (and attack id, if given).
func _hits_by(ev: Dictionary, attacker: Node, victim: Node, attack_id: StringName = &"") -> Array:
	var out := []
	for h in _hits(ev, victim, attack_id):
		if (h[1] as HitInfo).attacker == attacker:
			out.append(h)
	return out


## Seraph swings its first lance thrust at `def_m` at frame `swing`; the
## defender presses F at frame `parry` (-1: never).
func _swing_into(att: MechMotor, def_m: MechMotor, ev: Dictionary, frames: int, swing: int, parry: int, extra := Callable()) -> void:
	await _frames(ev, frames, func(i: int) -> void:
		_aim(att, def_m)
		_aim(def_m, att)
		att.command.attack_pressed = i == swing
		att.command.attack_held = i == swing
		def_m.command.parry_pressed = i == parry
		if extra.is_valid():
			extra.call(i))


# ------------------------------------------------------------------ T46

## Round 6a: 流光镜盾 / 熔爪截击 / 共生龟甲 / 孢囊爆散, quick + charged spear,
## weak ram, 熔炉喷焰.
func t46_round6_defence_moves(res: Dictionary) -> void:
	var l1 := load(L1) as AttackDefinition
	var orbital := load(ORBITAL) as AttackDefinition
	var pulse := load(PULSE) as AttackDefinition
	# ---------------- PALE SERAPH 流光镜盾
	var d := _mech(&"seraph", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 20))
	var az := _mech(&"azure", 1, Vector3(0, 0.2, 20), Vector3(0, 0.2, 30))
	await r._ticks(25)
	var dc := _cs(d)
	var mk := dc.kit as MirrorKit
	var mc := mk.cfg()
	var guard := func(_i: int) -> void:
		_aim(d, az)
		d.command.guard_held = true
	var ev := _rec()
	await _frames(ev, 6, guard)
	var en0 := d.en
	var hp0 := dc.health.hp
	var h1 := _hit(az, d, l1)
	r._check(res, dc.is_guarding() and h1.result == CombatTypes.HitResult.GUARDED and is_equal_approx(d.en, en0)
		and absf(mk.heat - l1.damage * mc.heat_per_damage) < 0.01 and is_equal_approx(hp0 - dc.health.hp, l1.damage * dc.profile.guard_damage_taken),
		"mirror guard: GUARDED for %.2f, EN untouched (%.0f → %.0f), heat %.1f (= %.0f × %.1f)" % [hp0 - dc.health.hp, en0, d.en, mk.heat, l1.damage, mc.heat_per_damage])
	# cools after the delay
	await _frames(ev, int((mc.cool_delay + 0.3) * 60.0), guard)
	r._check(res, mk.heat < l1.damage * mc.heat_per_damage - 0.3 * mc.cool_per_sec * 0.8, "heat cools while guarding without blocking (%.1f)" % mk.heat)
	# dash while guarding: the guard stays up
	var dash := {"dash": false, "guard": true}
	await _frames(ev, 20, func(i: int) -> void:
		guard.call(i)
		d.command.move = Vector3(1, 0, 0)
		d.command.dash_pressed = i == 2
		if d.get_state_name() == "GROUND_DASH":
			dash.dash = true
			dash.guard = dash.guard and dc.is_guarding())
	r._check(res, dash.dash and dash.guard, "guard + Shift: dashes with the mirror up (dash %s, guard kept %s)" % [dash.dash, dash.guard])
	d.command.move = Vector3.ZERO  # test commands persist: stop walking
	await _frames(ev, 20, guard)
	d.global_position = Vector3(0, 0.2, 30)  # back in line after the guard dash
	d.velocity = Vector3.ZERO
	await _frames(ev, 20, guard)
	# projectile refraction (×0.4 back to the shooter)
	mk.heat = 0.0
	ev = _rec()
	_shoot(az, pulse, az.global_position + Vector3(0, 2.6, 1.6), d.global_position + Vector3.UP * 2.2)
	await _frames(ev, 40, guard)
	_unrec()
	var g := _hits_by(ev, az, d, &"ao_pulse")
	var back := _hits_by(ev, d, az, &"ao_pulse")

	r._check(res, g.size() == 1 and g[0][2] == CombatTypes.HitResult.GUARDED and back.size() == 1 and absf(back[0][3] - pulse.damage * mc.projectile_refract_mult) < 0.01,
		"guarded shot refracts back to the shooter for %.1f (= %.0f × %.1f)" % [back[0][3] if back.size() else -1.0, pulse.damage, mc.projectile_refract_mult])
	# beam: no guard break, a light ray to the lock target (crosshair)
	mk.heat = 0.0
	dc.aim_target = az
	ev = _rec()
	var hp_d := dc.health.hp
	var hb := _hit(az, d, orbital)
	await _frames(ev, 2, guard)
	_unrec()
	var ray := _hits_by(ev, d, az, &"seraph_mirror_ray")
	r._check(res, hb.result == CombatTypes.HitResult.GUARDED and dc.is_guarding() and absf((hp_d - dc.health.hp) - orbital.damage * dc.profile.guard_damage_taken) < 0.01,
		"orbital beam on the mirror: GUARDED (no guard break), took %.1f" % (hp_d - dc.health.hp))
	r._check(res, ray.size() == 1 and ray[0][2] == CombatTypes.HitResult.HIT and absf(ray[0][3] - orbital.damage * mc.beam_reflect_mult) < 0.01
		and absf(mk.heat - orbital.damage * mc.heat_per_damage * mc.beam_heat_mult) < 0.01,
		"reflected light hits the locked caster for %.0f (= %.0f × %.1f); heat %.0f (beam ×%.1f)" % [ray[0][3] if ray.size() else -1.0, orbital.damage, mc.beam_reflect_mult, mk.heat, mc.beam_heat_mult])
	# no lock: the light follows the view point (crosshair)
	await _frames(ev, 40, guard)
	mk.heat = 0.0
	var guard_free := func(_i: int) -> void:
		d.command.guard_held = true
		d.command.face_dir = Vector3(0, 0, -1)
	dc.aim_target = null
	dc.view_point_valid = true
	var outs := []
	for vp in [az.global_position + Vector3.UP * 2.2, az.global_position + Vector3(25, 2.2, 0)]:
		dc.view_point = vp
		ev = _rec()
		_hit(az, d, orbital)
		await _frames(ev, 2, func(i: int) -> void:
			d.command.guard_held = true
			d.command.face_dir = Vector3(0, 0, -1))
		_unrec()
		outs.append(_hits_by(ev, d, az, &"seraph_mirror_ray").size())
		mk.heat = 0.0
		await _frames(ev, 30, guard_free)
	r._check(res, outs == [1, 0], "no lock: the light flies to the crosshair point (on the caster %d, aimed aside %d)" % outs)
	dc.view_point_valid = false
	dc.aim_target = az
	# overheat: pose kept, no reduction, back after cooling to 0
	mk.heat = mc.max_heat - 2.0
	var h2 := _hit(az, d, l1)

	var guarding_hot := dc.is_guarding() and mk.overheated
	var hp_b := dc.health.hp
	var h3 := _hit(az, d, l1)
	r._check(res, h2.result == CombatTypes.HitResult.GUARDED and guarding_hot and h3.result == CombatTypes.HitResult.HIT
		and is_equal_approx(hp_b - dc.health.hp, l1.damage),
		"heat %.0f → overheated: still GUARD, next hit %s for full %.0f" % [mc.max_heat, CombatTypes.RESULT_NAMES[h3.result], hp_b - dc.health.hp])
	var cool := {"t": -1}
	await _frames(ev, int((mc.max_heat / mc.overheat_cool_per_sec + 0.6) * 60.0), func(i: int) -> void:
		guard.call(i)
		if cool.t < 0 and not mk.overheated:
			cool.t = i)
	var h4 := _hit(az, d, l1)
	r._check(res, cool.t > 0 and absf(cool.t / 60.0 - mc.max_heat / mc.overheat_cool_per_sec) < 0.6 and h4.result == CombatTypes.HitResult.GUARDED,
		"mirror back after %.2f s of cooling to 0 (≈ %.1f s + stagger); guards again" % [cool.t / 60.0, mc.max_heat / mc.overheat_cool_per_sec])
	# ultimate attacks pass the mirror outside judgment; judgment stops them, heat ×0.5
	var ua := l1.duplicate() as AttackDefinition
	ua.ultimate_attack = true
	await _frames(ev, 50, guard)
	mk.heat = 0.0
	var h5 := _hit(az, d, ua)
	await _frames(ev, 50, guard)
	dc.health.hp = dc.health.max_hp * 0.25
	await _frames(ev, 3, guard)
	dc.ultimate.enter_judgment()
	await _frames(ev, 3, guard)
	mk.heat = 0.0
	var h6 := _hit(az, d, ua)
	r._check(res, h5.result == CombatTypes.HitResult.HIT and dc.ultimate.in_judgment() and h6.result == CombatTypes.HitResult.GUARDED
		and absf(mk.heat - ua.damage * mc.heat_per_damage * mc.judgment_heat_mult) < 0.01,
		"ultimate attack: %s outside judgment, %s in judgment (heat %.1f = ×%.1f)" % [CombatTypes.RESULT_NAMES[h5.result], CombatTypes.RESULT_NAMES[h6.result], mk.heat, mc.judgment_heat_mult])
	# the F parry ignores the heat
	await _free([d, az])
	d = _mech(&"seraph", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 20))
	az = _mech(&"azure", 1, Vector3(0, 0.2, 20), Vector3(0, 0.2, 30))
	await r._ticks(25)
	dc = _cs(d)
	mk = dc.kit as MirrorKit
	mk.heat = mc.max_heat
	mk.overheated = true
	ev = _rec()
	_shoot(az, pulse, az.global_position + Vector3(0, 2.6, 1.6), d.global_position + Vector3.UP * 2.2)
	await _frames(ev, 30, func(i: int) -> void:
		_aim(d, az)
		d.command.parry_pressed = i == 4)
	_unrec()
	var pr := _hits_by(ev, az, d, &"ao_pulse")
	r._check(res, pr.size() >= 1 and pr[0][2] == CombatTypes.HitResult.REFLECTED, "overheated mirror: the F parry still refracts a shot (%s)" % (CombatTypes.RESULT_NAMES[pr[0][2]] if pr.size() else "no hit"))
	await _free([d, az])

	# ---------------- HELLFANG 熔爪截击 / weak ram / 熔炉喷焰
	var hf := _mech(&"hellfang", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 26.5))
	var sa := _mech(&"seraph", 1, Vector3(0, 0.2, 26.5), Vector3(0, 0.2, 30))
	await r._ticks(25)
	var hc := _cs(hf)
	var hk := hc.kit as HeatKit
	var hcfg := hk.cfg()
	r._check(res, is_equal_approx(hc.profile.parry_window, 0.14) and not hc.profile.parry_reflects, "HELLFANG parry window %.2f s, swallows shots" % hc.profile.parry_window)
	ev = _rec()
	var probe := {"axe_start": -1, "axe_active": -1}
	await _swing_into(sa, hf, ev, 70, 10, 13, func(i: int) -> void:
		if i == 24:
			hf.command.attack_pressed = true
			hf.command.attack_held = true
		else:
			hf.command.attack_held = false)
	_unrec()
	var ph := _hits(ev, hf, &"seraph_l1")
	for s in ev.started:
		if s[1] == hf and s[2] == &"hf_axe1" and probe.axe_start < 0:
			probe.axe_start = s[0]
	for s in ev.active:
		if s[1] == hf and s[2] == &"hf_axe1" and probe.axe_active < 0:
			probe.axe_active = s[0]
	var axe := hc.profile.light_combo
	var quick_f: int = probe.axe_active - probe.axe_start
	r._check(res, ph.size() == 1 and ph[0][2] == CombatTypes.HitResult.PARRIED and _kit_events(ev, &"claw_catch") == 1,
		"melee caught: PARRIED + 截击 (%s)" % (CombatTypes.RESULT_NAMES[ph[0][2]] if ph.size() else "no hit"))
	var st_seen := false
	for s in ev.status:
		if s[1] == sa and s[2] == &"bitten":
			st_seen = true
	r._check(res, st_seen and absf(quick_f / 60.0 - axe.windup * hcfg.parry_catch_windup_mult) <= 2.0 / 60.0 and _hits(ev, sa, &"hf_axe1").size() == 1,
		"caught attacker bitten; next axe windup %.2f s (= %.2f × %.1f) and it lands" % [quick_f / 60.0, axe.windup, hcfg.parry_catch_windup_mult])
	# swallowed shot: heat +6, grapple cooldown -1 s
	await r._ticks(60)
	hc.restore_full()
	await r._ticks(2)
	var hook := hc.profile.skill
	hc.set_cooldown(hook.cd_id(), 2.0)
	var heat0 := hk.heat
	ev = _rec()
	_shoot(sa, pulse, hf.global_position + Vector3(0, 2.6, -8.0), hf.global_position + Vector3.UP * 2.2)
	await _frames(ev, 20, func(i: int) -> void:
		hf.command.face_dir = Vector3(0, 0, -1)
		hf.command.parry_pressed = i == 2)
	_unrec()
	var sw := _hits(ev, hf, &"ao_pulse")
	r._check(res, sw.size() == 1 and sw[0][2] == CombatTypes.HitResult.PARRIED and absf(hk.heat - heat0 - hcfg.parry_shot_heat) < 1.0
		and hc.get_cooldown(hook.cd_id()) < 2.0 - hcfg.parry_shot_hook_cut - 0.2,
		"shot swallowed (%s): heat +%.0f, grapple cooldown %.2f s (2.0 − %.0f − elapsed)" % [CombatTypes.RESULT_NAMES[sw[0][2]] if sw.size() else "none", hk.heat - heat0, hc.get_cooldown(hook.cd_id()), hcfg.parry_shot_hook_cut])
	# EN guard break still applies to HELLFANG
	await r._ticks(30)
	hc.restore_full()
	await r._ticks(2)
	ev = _rec()
	await _swing_into(sa, hf, ev, 30, 4, -1, func(_i: int) -> void:
		hf.command.guard_held = true
		hf.en = 0.0)
	_unrec()
	hf.command.guard_held = false
	var gb := _hits(ev, hf, &"seraph_l1")
	r._check(res, gb.size() == 1 and gb[0][2] == CombatTypes.HitResult.GUARD_BREAK, "HELLFANG guard with EN 0 still breaks (%s)" % (CombatTypes.RESULT_NAMES[gb[0][2]] if gb.size() else "no hit"))
	await _free([hf, sa])
	# tap swings on the press frame; a hold converts it into the weak ram below 60 heat
	hf = _mech(&"hellfang", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 20))
	sa = _mech(&"seraph", 1, Vector3(0, 0.2, 20), Vector3(0, 0.2, 30))
	await r._ticks(25)
	hc = _cs(hf)
	hk = hc.kit as HeatKit
	ev = _rec()
	await _frames(ev, 40, func(i: int) -> void:
		_aim(hf, sa)
		hf.command.attack_pressed = i == 0
		hf.command.attack_held = i == 0)
	_unrec()
	var tap_f := -1
	for s in ev.started:
		if s[1] == hf and s[2] == &"hf_axe1":
			tap_f = s[0]
			break
	r._check(res, tap_f == 0, "tap: the axe starts on the press frame (frame %d, no tap / hold wait)" % tap_f)
	await r._ticks(40)
	hc.restore_full()
	await r._ticks(2)
	hk.heat = 0.0
	ev = _rec()
	var rp := {"heat": -1.0}
	await _frames(ev, 90, func(i: int) -> void:
		_aim(hf, sa)
		hf.command.attack_pressed = i == 0
		hf.command.attack_held = i < 30
		if rp.heat < 0.0 and hc.attack and hc.attack.id == &"hf_ram_lite":
			rp.heat = hk.heat)
	_unrec()
	var lite := hc.profile.attack_hold_fallback
	var lh := _hits(ev, sa, &"hf_ram_lite")
	r._check(res, _started(ev, hf, &"hf_axe1") == 1 and _started(ev, hf, &"hf_ram_lite") == 1 and _started(ev, hf, &"hf_ram") == 0
		and absf(rp.heat - lite.heat_cost) < 0.5,
		"heat 0 + hold: first swing converts into the weak ram (heat %.0f = ram %.0f, axe refunded)" % [rp.heat, lite.heat_cost])
	r._check(res, lh.size() == 1 and absf(lh[0][3] - lite.damage) < 0.01 and not lite.guard_break and hc.get_cooldown(&"hf_ram") > 0.0,
		"weak ram hits for %.0f (no guard break), shares the ram cooldown (%.1f s left)" % [lh[0][3] if lh.size() else -1.0, hc.get_cooldown(&"hf_ram")])
	hk.heat = 70.0
	ev = _rec()
	await _frames(ev, 30, func(i: int) -> void:
		_aim(hf, sa)
		hf.command.attack_pressed = i == 0
		hf.command.attack_held = i < 25)
	_unrec()
	r._check(res, _started(ev, hf, &"hf_ram") == 0 and _started(ev, hf, &"hf_ram_lite") == 0, "full ram blocked by the shared cooldown")
	await _free([hf, sa])
	# 熔炉喷焰: heat × 0.35 in the cone, heat dumped; not below 30
	hf = _mech(&"hellfang", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 25))
	sa = _mech(&"seraph", 1, Vector3(0, 0.2, 25), Vector3(0, 0.2, 30))
	var side := _mech(&"seraph", 1, Vector3(3.5, 0.2, 28.5), Vector3(0, 0.2, 30))  # inside the box, outside the 70° cone
	await r._ticks(25)
	hc = _cs(hf)
	hk = hc.kit as HeatKit
	var flame := hc.profile.skill_hold
	hk.heat = 20.0
	ev = _rec()
	await _frames(ev, 40, func(i: int) -> void:
		_aim(hf, sa)
		_press_skill(hf, 30).call(i))
	_unrec()
	r._check(res, _started(ev, hf, &"hf_flame") == 0, "熔炉喷焰 needs %.0f heat (none at 20)" % flame.min_heat)
	await r._ticks(20)
	hk.heat = 80.0
	hk._since_gain = 0.0
	ev = _rec()
	var fp := {"heat": -1.0}
	await _frames(ev, 60, func(i: int) -> void:
		_aim(hf, sa)
		_press_skill(hf, 30).call(i)
		if fp.heat < 0.0 and _started(ev, hf, &"hf_flame") == 0:
			hk._since_gain = 0.0  # keep the heat at 80 while the hold decides (no idle cooling)
		elif fp.heat < 0.0 and _started(ev, hf, &"hf_flame") == 1:
			fp.heat = hk.heat)
	_unrec()
	var fh := _hits(ev, sa, &"hf_flame")
	r._check(res, fh.size() == 1 and absf(fh[0][3] - 80.0 * flame.heat_damage_per_heat) < 0.05 and _hits(ev, side, &"hf_flame").is_empty() and hk.heat < 1.0,
		"熔炉喷焰 at heat 80: %.1f to the target in the cone (= 80 × %.2f), side target untouched, heat → %.0f" % [fh[0][3] if fh.size() else -1.0, flame.heat_damage_per_heat, hk.heat])
	await _free([hf, sa, side])

	# ---------------- VERDANT 共生龟甲 / 孢囊爆散
	var va := _mech(&"verdant", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 26.5))
	sa = _mech(&"seraph", 1, Vector3(0, 0.2, 26.5), Vector3(0, 0.2, 30))
	var near := _mech(&"seraph", 1, Vector3(-6, 0.2, 36), Vector3(0, 0.2, 30))
	await r._ticks(25)
	var vc := _cs(va)
	var dk := vc.kit as DeployKit
	var tspec := (vc.profile.skill as AttackDefinition).deploy_spec
	var tu := Deployables.spawn_turret(vc, tspec, Vector3(-4, 0.2, 34))
	await r._ticks(int(tspec.arm_time * 60.0) + 20)
	var picked := tu.target
	dk.wall_cooldown_left = 99.0  # no shield wall in the way of the melee probe
	ev = _rec()
	await _swing_into(sa, va, ev, 24, 2, -1, func(_i: int) -> void:
		va.command.guard_held = true)
	_unrec()
	var vg := _hits(ev, va, &"seraph_l1")
	r._check(res, vg.size() == 1 and vg[0][2] == CombatTypes.HitResult.GUARDED and picked == near and tu.target == sa and tu.alert_left > 0.0,
		"block alerts the turret: target %s → attacker (alert %.1f s, ×%.1f fire rate)" % [picked.name if picked else "none", tu.alert_left, dk.cfg().alert_rate_mult])
	r._check(res, is_equal_approx(vc.profile.guard_speed_mult, 0.3), "turtle guard moves at ×%.2f" % vc.profile.guard_speed_mult)
	va.command.guard_held = false
	await r._ticks(40)
	vc.restore_full()
	await r._ticks(5)
	ev = _rec()
	await _swing_into(sa, va, ev, 30, 10, 13)
	_unrec()
	var vp := _hits(ev, va, &"seraph_l1")
	r._check(res, vp.size() == 1 and vp[0][2] == CombatTypes.HitResult.PARRIED and _kit_events(ev, &"spore_burst") == 1
		and _cs(sa).status.has(&"spore_snare"),
		"parry → 孢囊爆散: attacker snared (%s)" % _cs(sa).status.get_ids())
	# internal cooldown: a second parry right away does not burst again
	await r._ticks(20)
	sa.global_position = Vector3(0, 0.2, 26.5)
	sa.velocity = Vector3.ZERO
	await r._ticks(2)
	ev = _rec()
	await _swing_into(sa, va, ev, 30, 10, 13)
	_unrec()
	r._check(res, _hits(ev, va, &"seraph_l1").size() == 1 and _kit_events(ev, &"spore_burst") == 0 and dk.spore_cd_left > 0.0,
		"second parry within %.0f s: no burst (cooldown %.1f s left)" % [dk.cfg().spore_cooldown, dk.spore_cd_left])
	# swallowed shot (no refraction)
	ev = _rec()
	_shoot(sa, pulse, va.global_position + Vector3(0, 2.6, -8.0), va.global_position + Vector3.UP * 2.2)
	await _frames(ev, 20, func(i: int) -> void:
		va.command.face_dir = Vector3(0, 0, -1)
		va.command.parry_pressed = i == 2)
	_unrec()
	var vs := _hits(ev, va, &"ao_pulse")
	r._check(res, vs.size() == 1 and vs[0][2] == CombatTypes.HitResult.PARRIED, "VERDANT parry swallows a shot (%s)" % (CombatTypes.RESULT_NAMES[vs[0][2]] if vs.size() else "none"))
	await _free([va, sa, near, tu])

	# ---------------- 终审之矛: quick 0.4 s, hold up to 0.9 s (farther, harder)
	var spear_out := []
	for hold in [false, true]:
		var s := _mech(&"seraph", 0, Vector3(0, 0.2, 50), Vector3(0, 0.2, 0))
		var t := _mech(&"seraph", 1, Vector3(0, 0.2, 12), Vector3(0, 0.2, 50))
		await r._ticks(25)
		var sc := _cs(s)
		sc.health.hp = sc.health.max_hp * 0.25
		await r._ticks(3)
		sc.ultimate.enter_judgment()
		await r._ticks(2)
		ev = _rec()
		await _frames(ev, 120, func(i: int) -> void:
			_aim(s, t)
			s.command.skill_pressed = i == 0
			s.command.skill_held = hold and i < 70)
		_unrec()
		var st_f := -1
		var ac_f := -1
		for x in ev.started:
			if x[1] == s and x[2] == &"seraph_final_spear":
				st_f = x[0]
		for x in ev.active:
			if x[1] == s and x[2] == &"seraph_final_spear":
				ac_f = x[0]
		var sh := _hits(ev, t, &"seraph_final_spear")
		spear_out.append([ac_f - st_f, sh[0][3] if sh.size() else 0.0, 50.0 - s.global_position.z])
		await _free([s, t])
	var spear := load("res://resources/combat/seraph_final_spear.tres") as AttackDefinition
	var judg := (load("res://resources/combat/pale_seraph_ultimate.tres") as UltimateDefinition).damage_mult
	r._info("spear quick: %d frames to active, dmg %.1f, travelled %.1f m | held: %d frames, dmg %.1f, travelled %.1f m" % (spear_out[0] + spear_out[1]))
	r._check(res, absf(spear_out[0][0] / 60.0 - spear.windup) <= 2.0 / 60.0 and spear_out[0][1] == 0.0,
		"quick spear: out after %.2f s (data %.2f), 27 m reach falls short of a target 38 m away" % [spear_out[0][0] / 60.0, spear.windup])
	r._check(res, absf(spear_out[1][0] / 60.0 - spear.hold_windup_max) <= 2.0 / 60.0
		and absf(spear_out[1][1] - spear.damage * spear.hold_damage_max_mult * judg) < 0.1,
		"held spear: out after %.2f s (max %.2f), reaches it for %.1f (= %.0f × %.3f × %.2f)" % [spear_out[1][0] / 60.0, spear.hold_windup_max, spear_out[1][1], spear.damage, spear.hold_damage_max_mult, judg])


# ------------------------------------------------------------------ T47

## Round 6c (standard tempo package): hit-confirm cancels, cooldowns ×0.75,
## quicker deploy / charge, HP ×0.85, EN regen delay 0.35 s.
func t47_round6_tempo(res: Dictionary) -> void:
	var l1 := load(L1) as AttackDefinition
	# 命中取消: a landed hit opens dash / skill cancels at once; a whiff waits for cancel_time
	var outs := {}
	for kind in ["hit_dash", "whiff_dash", "hit_skill"]:
		var a := _mech(&"seraph", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 26.5))
		var b := _mech(&"seraph", 1, Vector3(0, 0.2, 26.5) if kind != "whiff_dash" else Vector3(0, 0.2, 10), Vector3(0, 0.2, 30))
		await r._ticks(25)
		var ac := _cs(a)
		var ev := _rec()
		var p := {"cancel_f": -1, "hit_f": -1}
		await _frames(ev, 40, func(i: int) -> void:
			_aim(a, b)
			a.command.attack_pressed = i == 0
			a.command.attack_held = i == 0
			# edges are OR-ed in like PlayerBrain does: a press inside the hit's
			# hitstop is kept until the mech runs again
			if i == 11:
				if kind == "hit_skill":
					a.command.skill_pressed = true
				else:
					a.command.dash_pressed = true
			if p.cancel_f < 0 and i > 11:
				if kind == "hit_skill" and ac.attack and ac.attack.id == &"seraph_dash_slash":
					p.cancel_f = i
				elif kind != "hit_skill" and a.state == MechMotor.MotionState.GROUND_DASH:
					p.cancel_f = i)
		_unrec()
		var hits := _hits(ev, b, &"seraph_l1")
		p.hit_f = hits[0][0] if hits.size() else -1
		outs[kind] = [p.hit_f, p.cancel_f, _kit_events(ev, &"hit_cancel")]
		await _free([a, b])
	var cancel_f := int(l1.cancel_time * 60.0)
	r._info("hit-cancel probes [hit frame, cancel frame, events]: %s (cancel_time %d frames)" % [outs, cancel_f])
	r._check(res, outs.hit_dash[0] >= 0 and outs.hit_dash[1] > 0 and outs.hit_dash[1] < cancel_f and outs.hit_dash[2] == 1,
		"landed thrust: dash cancels at frame %d (cancel_time frame %d)" % [outs.hit_dash[1], cancel_f])
	r._check(res, outs.whiff_dash[0] < 0 and (outs.whiff_dash[1] < 0 or outs.whiff_dash[1] >= cancel_f) and outs.whiff_dash[2] == 0,
		"whiffed thrust: no early cancel (dash at frame %d)" % outs.whiff_dash[1])
	r._check(res, outs.hit_skill[0] >= 0 and outs.hit_skill[1] > 0 and outs.hit_skill[1] < cancel_f,
		"landed thrust: X cancels into the dash slash at frame %d" % outs.hit_skill[1])
	# data: HP ×0.85, cooldowns ×0.75, quicker deploys / charge, regen delay
	var hp := {}
	for id: StringName in MechFactory.MECH_IDS:
		var m := _mech(id, 0, Vector3(0, 0.2, 30))
		await r._ticks(2)
		hp[id] = _cs(m).health.max_hp
		await _free([m])
	r._check(res, hp == {&"seraph": 255.0, &"hellfang": 290.0, &"verdant": 305.0, &"azure": 240.0}, "HP ×0.85: %s" % hp)
	var cds := {
		"seraph_dash_slash.tres": 1.9, "azure/ao_missiles.tres": 5.3, "azure/ao_orbital.tres": 3.8,
		"azure/ao_backstep.tres": 4.5, "azure/ao_rail.tres": 0.6, "verdant/va_turret.tres": 4.5,
		"verdant/va_zone.tres": 10.5, "hellfang/hf_hook.tres": 2.3, "hellfang/hf_ram.tres": 3.0, "hellfang/hf_ram_lite.tres": 3.0,
	}
	var bad := []
	for f in cds:
		var d := load("res://resources/combat/" + f) as AttackDefinition
		if not is_equal_approx(d.cooldown, cds[f]):
			bad.append("%s %.2f" % [f, d.cooldown])
	var hook := load("res://resources/combat/hellfang/hf_hook.tres") as AttackDefinition
	var turret := load("res://resources/combat/verdant/va_turret.tres") as AttackDefinition
	var zone := load("res://resources/combat/verdant/va_zone.tres") as AttackDefinition
	var azp := load("res://resources/combat/azure_combat.tres") as CombatProfile
	var dcfg := DeployConfig.new()
	var mp := MechMovementProfile.new()
	r._check(res, bad.is_empty() and is_equal_approx(hook.grapple_spec.miss_cooldown, 1.4),
		"cooldowns ×0.75 (grapple miss %.1f s)%s" % [hook.grapple_spec.miss_cooldown, "" if bad.is_empty() else " — off: %s" % [bad]])
	r._check(res, is_equal_approx(turret.windup, 0.6) and is_equal_approx(zone.windup, 0.45) and is_equal_approx(azp.charge_time, 1.2) and is_equal_approx(mp.regen_delay, 0.35),
		"turret windup %.2f s, zone %.2f s, rail full charge %.1f s, EN regen delay %.2f s" % [turret.windup, zone.windup, azp.charge_time, mp.regen_delay])
	r._check(res, is_equal_approx(CombatProfile.new().guard_break_stagger, 0.6) and is_equal_approx(CombatProfile.new().parry_whiff_recovery, 0.3)
		and is_equal_approx(dcfg.wall_cooldown, 4.5),
		"guard-break stagger 0.6 s, whiffed parry 0.3 s, shield wall cooldown %.1f s" % dcfg.wall_cooldown)


# ------------------------------------------------------------------ T48

## Round 7: HELLFANG's grapple leads a walking target and steers at it;
## a dash (mid-dash at launch, or during the flight) shakes both off.
func t48_hook_assist(res: Dictionary) -> void:
	var hook := load("res://resources/combat/hellfang/hf_hook.tres") as AttackDefinition
	var plain := hook.duplicate(true) as AttackDefinition  # the round-5 claw: straight, no lead
	plain.grapple_spec.lead_time_max = 0.0
	plain.grapple_spec.homing_deg = 0.0
	plain.grapple_spec.radius = 0.9
	var outs := {}
	for kind in ["walk_round5", "walk", "walk_air", "dash_in_flight", "dash_at_launch"]:
		var h := _mech(&"hellfang", 0, Vector3(0, 0.2, 30), Vector3(0, 0.2, 12))
		var t := _mech(&"seraph", 1, Vector3(-10, 0.2, 12) if kind != "walk_air" else Vector3(-10, 6.2, 12))
		await r._ticks(20)
		var hc := _cs(h)
		if kind == "walk_round5":
			hc.profile = hc.profile.duplicate() as CombatProfile
			hc.profile.skill = plain
		if kind == "walk_air":
			t.set_hover_lock(true)
		var ev := _rec()
		var p := {"launch": -1}
		await _frames(ev, 90, func(i: int) -> void:
			_aim(h, t)
			t.command.move = Vector3(1, 0, 0)  # walk sideways at full speed
			h.command.skill_pressed = i == 20
			h.command.skill_held = i == 20
			if p.launch < 0:
				for s in ev.spawned:
					if s[2] == &"grapple":
						p.launch = s[0]
			if kind == "dash_in_flight" and p.launch >= 0 and i == p.launch + 1:
				t.command.dash_pressed = true
			if kind == "dash_at_launch" and i == 26:
				t.command.dash_pressed = true)
		_unrec()
		t.command.move = Vector3.ZERO
		var g := _hits(ev, t, hook.id)
		outs[kind] = [g.size() > 0 and g[0][2] == CombatTypes.HitResult.HIT, _kit_events(ev, &"grapple_miss"), _kit_events(ev, &"grapple_shaken"), p.launch]
		await _free([h, t])
	r._info("hook vs a target walking sideways at 18 m [grabbed, misses, shaken, launch frame]: %s" % [outs])
	r._check(res, not outs.walk_round5[0] and outs.walk_round5[1] == 1, "round-5 claw (straight, no lead) misses the walking target")
	r._check(res, outs.walk[0] and outs.walk[1] == 0, "round-7 claw (lead %.1f s, homing %.0f°/s, radius %.1f m) grabs it" % [hook.grapple_spec.lead_time_max, hook.grapple_spec.homing_deg, hook.grapple_spec.radius])
	r._check(res, outs.walk_air[0], "grabs a target hovering 6 m up while it drifts sideways")
	r._check(res, not outs.dash_in_flight[0] and outs.dash_in_flight[1] == 1 and outs.dash_in_flight[2] == 1, "a dash during the flight shakes the steering off → miss")
	r._check(res, not outs.dash_at_launch[0] and outs.dash_at_launch[1] == 1, "a target mid-dash at launch gets no lead / homing → miss")
