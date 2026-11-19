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


func setup(p_motor: MechMotor, p_targeting: TargetingSystem) -> void:
	motor = p_motor
	combat = motor.get_node(^"CombatStateMachine")
	targeting = p_targeting
	CombatEvents.hit_resolved.connect(_on_hit)
	CombatEvents.parried.connect(_on_parried)
	CombatEvents.ultimate_phase.connect(_on_ult)
	CombatEvents.mech_died.connect(_on_died)


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


func show_overlay(text: String) -> void:
	_overlay.text = text
	_overlay.visible = true


func _process(delta: float) -> void:
	if motor == null:
		return
	# layout from the viewport size every frame (robust to window resizes)
	var vp := get_viewport().get_visible_rect().size
	_bottom.position = Vector2(vp.x * 0.5 - 220.0, vp.y - 150.0)
	_target_box.position = Vector2(vp.x * 0.5 - 200.0, 18.0)
	_callout.position = Vector2(vp.x * 0.5 - 400.0, vp.y * 0.30)
	_overlay.position = Vector2(vp.x * 0.5 - 500.0, vp.y * 0.42)
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
				txt = "圣骸回响 已用尽"
		_ult.text = txt
	var t := targeting.current if targeting and targeting.has_target() else null
	var tc := DamageSystem.get_combat(t)
	_target_box.visible = tc != null
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
		show_overlay("机体沉默 — 按 F7 重开")
	else:
		var alive := 0
		for m in TeamRules.get_valid_targets(motor, &"mechs"):
			alive += 1
		if alive == 0:
			show_overlay("全部敌机已击破 — 按 F7 重开")
