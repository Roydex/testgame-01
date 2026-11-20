extends Node
## Scripted phase-3a showcase in the real rendered skill lab
## (`res://scenes/test/skill_lab.tscn -- --skill-demo`). Drives the player
## through MechCommand only, swaps through the three new mechs, saves
## screenshots to docs/screenshots/skill_*.png, then measures the frame rate
## with two turrets firing, a missile salvo and an orbital strike live (P12).

var scene: Node3D
var out_dir: String
var log: PackedStringArray = []
var _frame_times: PackedFloat32Array = []
var _measure := false
var _skip := 0


func _process(delta: float) -> void:
	if _skip > 0:
		_skip -= 1
	elif _measure:
		_frame_times.append(delta)


func run(p_scene: Node3D) -> void:
	scene = p_scene
	out_dir = ProjectSettings.globalize_path("res://docs/screenshots")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	CombatEvents.hit_resolved.connect(func(h: HitInfo): log.append("%.2f %s→%s %s %s %.1f" % [
		Time.get_ticks_msec() / 1000.0, h.attacker.name if h.attacker else "?", h.victim.name if h.victim else "?",
		h.attack.display_name, CombatTypes.RESULT_NAMES[h.result], h.final_damage]))
	CombatEvents.kit_event.connect(func(m: Node3D, id: StringName): log.append("%.2f %s kit %s" % [Time.get_ticks_msec() / 1000.0, m.name, id]))
	_sequence.call_deferred()


func _partner() -> MechMotor:
	return scene.dummies[0]


func _setup_round(id: StringName, partner_mode: int) -> void:
	scene.swap_player(id)
	await get_tree().physics_frame
	scene.brain.enabled = false
	scene.rig.mouse_enabled = false
	var p := _partner()
	(p.get_node(^"SparringBrain") as SparringBrain).mode = partner_mode
	(scene.dummies[1].get_node(^"SparringBrain") as SparringBrain).mode = SparringBrain.Mode.PASSIVE
	scene.dummies[1].global_position = Vector3(60, 0.2, 60)
	scene.motor.reset_to(Vector3(0, 0.2, 30))
	p.reset_to(Vector3(0, 0.2, 12))
	scene.targeting._set_target(p, "demo")
	await _hold(0.6)


func _cmd() -> MechCommand:
	return scene.motor.command


func _face() -> void:
	var p := _partner()
	var to: Vector3 = p.global_position - scene.motor.global_position
	_cmd().face_dir = Vector3(to.x, 0, to.z)
	scene.combat.aim_target = p


func _hold(seconds: float, each := Callable()) -> void:
	var t := 0.0
	while t < seconds:
		_face()
		if each.is_valid():
			each.call(t)
		await get_tree().physics_frame
		t += 1.0 / 60.0


func _shot(name: String) -> void:
	_skip = 3
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("skill_%s.png" % name))
	log.append("[shot] skill_%s.png" % name)


func _sequence() -> void:
	# --- 02 HELLFANG: grapple, overdrive ram telegraph, overheat
	await _setup_round(&"hellfang", SparringBrain.Mode.PASSIVE)
	var hk := scene.combat.kit as HeatKit
	_cmd().skill_pressed = true
	await _hold(0.32)
	await _shot("hellfang_grapple")
	await _hold(1.2)
	scene.motor.reset_to(Vector3(0, 0.2, 26))
	await _hold(0.4)
	hk.add_heat(70.0)
	await _hold(0.6, func(t: float):
		_cmd().attack_pressed = t < 0.02
		_cmd().attack_held = true)
	await _shot("hellfang_ram_windup")
	await _hold(1.8, func(_t: float): _cmd().attack_held = false)
	hk.add_heat(100.0)
	await _hold(0.3)
	await _shot("hellfang_overheat")
	await _hold(1.6)
	# --- 03 VERDANT ARK: two turrets + restraint zone on the partner
	await _setup_round(&"verdant", SparringBrain.Mode.PASSIVE)
	for k in 2:
		_cmd().face_dir = Vector3(-1 + 2 * k, 0, -1)
		await _hold(0.05, func(_t: float):
			_cmd().face_dir = Vector3(-1 + 2 * k, 0, -1)
			_cmd().skill_pressed = true)
		await _hold(1.4)
		scene.combat._cooldowns.clear()  # demo only: skip the deploy cooldown
	await _hold(0.7, func(t: float):
		_cmd().skill_pressed = t < 0.02
		_cmd().skill_held = true)
	await _hold(0.8)
	await _shot("verdant_turrets_zone")
	await _hold(0.4, func(t: float): _cmd().attack_pressed = t < 0.02)
	await _shot("verdant_scatter")
	await _hold(0.6)
	# --- 04 AZURE ORACLE: rail laser, missiles, orbital circle (+ FPS window)
	await _setup_round(&"azure", SparringBrain.Mode.PASSIVE)
	await _hold(1.0, func(_t: float): _cmd().guard_held = true)
	await _shot("azure_rail_laser")
	await _hold(0.3, func(_t: float): _cmd().guard_held = false)
	await _hold(0.6)
	_cmd().skill_pressed = true
	await _hold(0.9)
	await _shot("azure_missiles")
	# playtest round 3: X held → raised view, the ghost marks the ground
	await _hold(1.0, func(t: float):
		_cmd().skill_pressed = t < 0.02
		_cmd().skill_held = true
		scene.brain.update_placement_aim(scene.combat))
	await _shot("azure_orbital_aim")
	await _hold(0.4, func(_t: float):
		_cmd().skill_held = false
		scene.brain.update_placement_aim(scene.combat))
	await _shot("azure_orbital_circle")
	await _hold(1.25)
	await _shot("azure_orbital_burn")  # playtest round 2: the circle keeps burning
	# --- playtest round 2: judgment + duel camera, shield wall, furnace burst
	await _setup_round(&"seraph", SparringBrain.Mode.PASSIVE)
	_partner().reset_to(Vector3(0, 0.2, 22))  # 8 m: inside the duel framing range
	await _hold(0.8)
	await _hold(0.05, func(t: float): _cmd().parry_pressed = t < 0.02)
	await _shot("seraph_parry_swing")
	await _hold(0.6)
	scene.combat.ultimate.enter_judgment()
	await _hold(0.3)
	await _hold(0.05, func(t: float): _cmd().parry_pressed = t < 0.02)
	await _shot("seraph_judgment_parry")
	await _hold(0.5)
	await _hold(1.2, func(t: float):
		_cmd().attack_pressed = fmod(t, 0.35) < 0.02
		_cmd().move = Vector3(1, 0, 0) if t < 0.6 else Vector3.ZERO)
	await _shot("seraph_judgment_duel")
	await _setup_round(&"verdant", SparringBrain.Mode.PASSIVE)
	await _hold(0.5, func(_t: float): _cmd().guard_held = true)
	await _hold(0.3, func(_t: float): _cmd().guard_held = false)
	await _shot("verdant_wall")
	await _setup_round(&"hellfang", SparringBrain.Mode.PASSIVE)
	_partner().reset_to(Vector3(0, 0.2, 26))
	var axe: AttackDefinition = load("res://resources/combat/hellfang/hf_axe1.tres")
	await _hold(0.7, func(t: float):
		_cmd().guard_held = true
		if absf(t - 0.2) < 0.01 or absf(t - 0.45) < 0.01:
			var h := HitInfo.new()
			h.attacker = _partner()
			h.victim = scene.motor
			h.attack = axe
			h.source_position = _partner().global_position
			h.direction = (scene.motor.global_position - _partner().global_position).normalized()
			DamageSystem.resolve(h))
	await _hold(0.2, func(_t: float): _cmd().guard_held = false)
	await _shot("hellfang_furnace_burst")
	await _hold(0.8)
	# --- P12: frame rate with the lab busy (turrets + missiles + strike + partners fighting)
	await _setup_round(&"verdant", SparringBrain.Mode.MELEE)
	scene._swap_partner(&"azure")
	await get_tree().physics_frame
	(_partner().get_node(^"SparringBrain") as SparringBrain).mode = SparringBrain.Mode.PASSIVE
	_partner().reset_to(Vector3(0, 0.2, 6))
	scene.set_practice(true)
	for k in 2:
		await _hold(0.05, func(_t: float):
			_cmd().face_dir = Vector3(-1 + 2 * k, 0, -1)
			_cmd().skill_pressed = true)
		await _hold(1.2)
		scene.combat._cooldowns.clear()
	_measure = true
	var pm := _partner()
	var pc := DamageSystem.get_combat(pm)
	(pm.get_node(^"SparringBrain") as SparringBrain).enabled = false  # scripted below
	await _hold(6.0, func(t: float):
		_cmd().attack_pressed = fmod(t, 0.7) < 0.02
		# the AZURE partner is driven by script here: pulse, a missile salvo, an orbital strike
		var to: Vector3 = scene.motor.global_position - pm.global_position
		pm.command.face_dir = Vector3(to.x, 0, to.z)
		pc.aim_target = scene.motor
		pm.command.attack_pressed = fmod(t, 0.3) < 0.02
		pm.command.skill_pressed = (t > 0.5 and t < 0.52) or (t > 2.5 and t < 2.52)
		pm.command.skill_held = t > 2.5 and t < 3.0)
	_measure = false
	await _shot("busy_lab")
	_report()


func _report() -> void:
	var n := _frame_times.size()
	var line := "no frames measured"
	if n > 0:
		var sorted := _frame_times.duplicate()
		sorted.sort()
		var total := 0.0
		for f in _frame_times:
			total += f
		var worst := sorted.slice(int(n * 0.99))
		var wsum := 0.0
		for f in worst:
			wsum += f
		line = "P12 busy lab (2 turrets, missiles, orbital, 2 partners): %d frames, avg %.0f FPS, 1%% low %.0f FPS, worst %.1f ms" % [
			n, n / total, worst.size() / maxf(wsum, 0.0001), sorted[n - 1] * 1000.0]
	log.append(line)
	var f := FileAccess.open(ProjectSettings.globalize_path("res://tests/logs/skill_demo.log"), FileAccess.WRITE)
	f.store_string("\n".join(log) + "\n")
	f.close()
	print(line)
	get_tree().quit()
