class_name CombatHud
extends CanvasLayer
## Player-facing combat HUD (prototype): HP / EN / ultimate, locked target
## status, short event call-outs, defeat / victory overlay.

var motor: MechMotor
var combat: CombatStateMachine
var targeting: TargetingSystem

var _hp: ProgressBar
var _en: ProgressBar
var _ult: Label
var _target_box: VBoxContainer
var _target_name: Label
var _target_hp: ProgressBar
var _callout: Label
var _callout_t := 0.0
var _overlay: Label
var _bottom: VBoxContainer
var _banner: Label
var _kit_label: Label
var _kit_bar: ProgressBar
var _warn: Label
var _connected := false


func setup(p_motor: MechMotor, p_targeting: TargetingSystem) -> void:
	motor = p_motor
	combat = motor.get_node(^"CombatStateMachine")
	targeting = p_targeting
	if _connected:
		return
	_connected = true
	CombatEvents.hit_resolved.connect(_on_hit)
	CombatEvents.parried.connect(_on_parried)
	CombatEvents.ultimate_phase.connect(_on_ult)
	CombatEvents.mech_died.connect(_on_died)
	CombatEvents.kit_event.connect(_on_kit_event)
	CombatEvents.riposte_window.connect(_on_riposte_window)


func _ready() -> void:
	layer = 9
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var bottom := VBoxContainer.new()
	bottom.custom_minimum_size = Vector2(440, 0)
	root.add_child(bottom)
	_bottom = bottom
	_hp = _bar(bottom, Color(0.35, 0.9, 0.45))
	_en = _bar(bottom, Color(0.35, 0.7, 1.0))
	_en.custom_minimum_size.y = 10
	_ult = _label(bottom, 17)
	_kit_bar = _bar(bottom, Color(1.0, 0.45, 0.15))
	_kit_bar.custom_minimum_size.y = 10
	_kit_label = _label(bottom, 16)
	_warn = _label(root, 26)
	_warn.custom_minimum_size = Vector2(800, 0)
	_warn.add_theme_color_override(&"font_color", Color(1.0, 0.35, 0.25))
	_target_box = VBoxContainer.new()
	_target_box.custom_minimum_size = Vector2(400, 0)
	root.add_child(_target_box)
	_target_name = _label(_target_box, 16)
	_target_hp = _bar(_target_box, Color(0.95, 0.35, 0.3))
	_callout = _label(root, 30)
	_callout.custom_minimum_size = Vector2(800, 0)
	_overlay = _label(root, 44)
	_overlay.custom_minimum_size = Vector2(1000, 0)
	_overlay.visible = false
	_banner = _label(root, 15)
	_banner.custom_minimum_size = Vector2(1200, 0)
	_banner.add_theme_color_override(&"font_color", Color(0.85, 0.95, 0.8))


func _bar(parent: Control, c: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 18)
	var fill := StyleBoxFlat.new()
	fill.bg_color = c
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	b.add_theme_stylebox_override(&"fill", fill)
	b.add_theme_stylebox_override(&"background", bg)
	parent.add_child(b)
	return b


func _label(parent: Control, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override(&"font", UiFont.get_font())
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	l.add_theme_constant_override(&"shadow_offset_x", 2)
	l.add_theme_constant_override(&"shadow_offset_y", 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func callout(text: String, color: Color = Color.WHITE, t: float = 0.8) -> void:
	_callout.text = text
	_callout.add_theme_color_override(&"font_color", color)
	_callout_t = t


func set_mode_banner(text: String) -> void:
	_banner.text = text


func show_overlay(text: String) -> void:
	_overlay.text = text
	_overlay.visible = true


func _process(delta: float) -> void:
	if motor == null:
		return
	# layout from the viewport size every frame (robust to window resizes)
	var vp := get_viewport().get_visible_rect().size
	_bottom.position = Vector2(vp.x * 0.5 - 220.0, vp.y - 190.0)
	_warn.position = Vector2(vp.x * 0.5 - 400.0, vp.y * 0.62)
	_target_box.position = Vector2(vp.x * 0.5 - 200.0, 18.0)
	_callout.position = Vector2(vp.x * 0.5 - 400.0, vp.y * 0.30)
	_overlay.position = Vector2(vp.x * 0.5 - 500.0, vp.y * 0.42)
	_banner.position = Vector2(vp.x * 0.5 - 600.0, 72.0)
	_callout_t = maxf(_callout_t - delta, 0.0)
	_callout.visible = _callout_t > 0.0
	var h := combat.health
	_hp.max_value = h.max_hp
	_hp.value = h.hp
	_en.max_value = motor.profile.max_en
	_en.value = motor.en
	var u := combat.ultimate
	if u == null:
		_ult.text = ""
	else:
		var txt := ""
		match u.phase:
			UltimateSystem.Phase.LOCKED:
				txt = "冠冕残缺 · HP ≤ %d%% 时觉醒" % int(u.definition.hp_threshold * 100.0)
			UltimateSystem.Phase.READY:
				txt = "【V】圣骸回响 · 冠冕补完 已就绪"
			UltimateSystem.Phase.WINDUP:
				txt = "冠冕补完中……"
			UltimateSystem.Phase.JUDGMENT:
				txt = "审判 %.1fs  ·  【X】终审之矛 ×%d" % [u.phase_time_left, u.spear_charges_left]
			UltimateSystem.Phase.OVERLOAD:
				txt = "圣骸过载 %.1fs（EN 不恢复，受伤 ×%.1f）" % [u.phase_time_left, u.definition.overload_damage_taken_mult]
			UltimateSystem.Phase.COOLDOWN:
				txt = "协议中断 · %.1fs 后可再次发动" % u.phase_time_left
			UltimateSystem.Phase.SPENT:
				txt = "圣骸回响 已用尽（F12 切到练习模式可不限次数）"
		_ult.text = txt
	_update_kit()
	_update_warnings()
	var t := targeting.current if targeting and targeting.has_target() else null
	var tc := DamageSystem.get_combat(t)
	_target_box.visible = tc != null
	if tc == null and t and t.get(&"health") is Health:
		var th := t.get(&"health") as Health
		_target_box.visible = true
		_target_name.text = "%s  [%s]" % [t.name, "%.0fs" % float(t.call(&"time_left")) if t.has_method(&"time_left") else ""]
		_target_hp.max_value = th.max_hp
		_target_hp.value = th.hp
	if tc:
		_target_name.text = "%s  [%s]%s" % [t.name, tc.get_state_name(),
			"  审判中" if tc.ultimate and tc.ultimate.in_judgment() else ""]
		_target_hp.max_value = tc.health.max_hp
		_target_hp.value = tc.health.hp


func _on_hit(hit: HitInfo) -> void:
	if hit.attacker == motor:
		match hit.result:
			CombatTypes.HitResult.GUARD_BREAK:
				callout("破防", Color(1.0, 0.7, 0.2))
			CombatTypes.HitResult.HIT:
				var vc := DamageSystem.get_combat(hit.victim)
				if vc and vc.offbalance_by == motor:
					callout("反击 ×%.1f" % combat.profile.counter_damage_mult, Color(1.0, 0.9, 0.4), 0.6)
	elif hit.victim == motor and hit.result == CombatTypes.HitResult.GUARD_BREAK:
		callout("被破防！", Color(1.0, 0.4, 0.3))


func _on_parried(defender: Node3D, attacker: Node3D, was_projectile: bool) -> void:
	if defender == motor:
		callout("折射！" if was_projectile else "招架！", Color(0.85, 0.95, 1.0))
	elif attacker == motor:
		callout("被招架", Color(1.0, 0.5, 0.4))


func _on_ult(mech: Node3D, phase: String) -> void:
	if mech == motor and phase == "JUDGMENT":
		callout("冠冕补完 · 审判开始", Color(1.0, 0.93, 0.6), 1.5)
	elif mech != motor and phase == "JUDGMENT":
		callout("警告：%s 进入审判状态" % mech.name, Color(1.0, 0.5, 0.3), 1.5)
	elif mech != motor and phase == "READY":
		callout("%s 的冠冕亮起" % mech.name, Color(1.0, 0.8, 0.4), 1.2)


func _on_died(mech: Node3D) -> void:
	if mech == motor:
		show_overlay("机体沉默 — 按 F7 重开（或 Esc 打开菜单）")
	else:
		var alive := 0
		for m in TeamRules.get_valid_targets(motor, &"mechs"):
			alive += 1
		if alive == 0:
			show_overlay("全部敌机已击破 — 按 F7 重开")


func _update_kit() -> void:
	var k := combat.kit
	var txt := k.hud_text() if k else ""
	_kit_label.text = txt
	_kit_label.visible = txt != ""
	var b := k.hud_bar() if k else -1.0
	_kit_bar.visible = b >= 0.0
	if b >= 0.0:
		_kit_bar.max_value = 1.0
		_kit_bar.value = b
		var fill := _kit_bar.get_theme_stylebox(&"fill") as StyleBoxFlat
		if fill and k is HeatKit:
			fill.bg_color = Color(1.0, 0.25, 0.1) if (k as HeatKit).is_scorching() or (k as HeatKit).is_overheated() else Color(1.0, 0.6, 0.2)
		elif fill:
			fill.bg_color = Color(0.5, 0.85, 1.0)


## Lock-on warnings for the player: anything aiming a major attack at them.
func _update_warnings() -> void:
	var w: PackedStringArray = []
	for m in get_tree().get_nodes_in_group(&"mechs"):
		var c := DamageSystem.get_combat(m)
		if c and m != motor and TeamRules.is_hostile(m, motor) and c.is_charging() and c.aim_target == motor:
			w.append("⚠ 磁轨瞄准中 %d%%" % int(c.charge_level * 100.0))
			break
	for o in get_tree().get_nodes_in_group(&"orbital_strikes"):
		var s := o as OrbitalStrike
		if s and is_instance_valid(s.owner_mech) and TeamRules.is_hostile(s.owner_mech, motor):
			var d := motor.global_position - s.global_position
			if Vector2(d.x, d.z).length() <= s.radius + 1.0:
				w.append("⚠ 轨道打击锁定 — 离开红圈" if s.is_locked() else "⚠ 轨道打击追踪中 — 等锁定再躲")
				break
	for p in get_tree().get_nodes_in_group(&"projectiles"):
		var pr := p as Projectile
		if pr and pr.homing_target == motor and pr.health and is_instance_valid(pr.owner_mech) and TeamRules.is_hostile(pr.owner_mech, motor):
			w.append("⚠ 导弹锁定")
			break
	_warn.text = "   ".join(w)
	_warn.visible = not w.is_empty()


func _on_riposte_window(mech: Node3D, target: Node3D, _duration: float) -> void:
	if mech == motor and target != null:
		callout("反刺！ 左键", Color(1.0, 0.95, 0.6), 0.6)


func _on_kit_event(mech: Node3D, id: StringName) -> void:
	if mech != motor:
		return
	match id:
		&"overheat":
			callout("过热！", Color(1.0, 0.4, 0.2), 1.0)
		&"grapple_miss":
			callout("钩爪落空", Color(1.0, 0.7, 0.5), 0.6)
		&"grapple_pull", &"grapple_drag":
			callout("钩中 · 硬直", Color(1.0, 0.55, 0.25), 0.6)
