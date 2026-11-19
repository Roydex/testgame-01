class_name DebugHud
extends CanvasLayer
## Movement debug overlay: motion / combat state, velocity, EN, height above
## ground, lock target, collision state, modifiers. Also draws the lock
## reticle and off-screen enemy indicators (those stay on when the text
## panel is hidden with F1).

var motor: MechMotor
var combat: CombatStateMachine
var targeting: TargetingSystem
var rig: CameraRig

var _panel: PanelContainer
var _label: Label
var _en_bar: ProgressBar
var _overlay: Control
var _help: Label
var _events: Array[String] = []


func setup(p_motor: MechMotor, p_combat: CombatStateMachine, p_targeting: TargetingSystem, p_rig: CameraRig) -> void:
	motor = p_motor
	combat = p_combat
	targeting = p_targeting
	rig = p_rig
	motor.motion_state_changed.connect(func(_o: int, n: int): _log_event("motion → " + MechMotor.STATE_NAMES[n]))
	motor.landed.connect(func(v: float, hard: bool): _log_event("landed %.1f m/s%s" % [v, " HARD" if hard else ""]))
	motor.en_exhausted.connect(func(): _log_event("EN EXHAUSTED"))
	targeting.target_changed.connect(func(_o: Node3D, n: Node3D, reason: String):
		_log_event("lock: %s (%s)" % [n.name if n else "none", reason]))


func _ready() -> void:
	layer = 10
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.set_content_margin_all(10)
	_panel.add_theme_stylebox_override(&"panel", sb)
	var vb := VBoxContainer.new()
	_panel.add_child(vb)
	_label = Label.new()
	_label.add_theme_font_override(&"font", UiFont.get_font())
	_label.add_theme_font_size_override(&"font_size", 15)
	vb.add_child(_label)
	_en_bar = ProgressBar.new()
	_en_bar.custom_minimum_size = Vector2(260, 16)
	_en_bar.show_percentage = false
	vb.add_child(_en_bar)
	add_child(_panel)

	_help = Label.new()
	_help.add_theme_font_override(&"font", UiFont.get_font())
	_help.add_theme_font_size_override(&"font_size", 13)
	_help.text = "WASD move | Mouse look (click to capture) | Esc / P pause | Space jump / hold ascend | C/Ctrl descend | Shift dash\nQ / MMB lock | E / R or wheel switch target | Z camera distance | LMB attack RMB guard F parry X dash-slash V ultimate | F1 HUD | F2 mech profile | F3 test stagger | F4 test action | F5 reset | K kill locked target | F6 test shooters | F5 refill | F7 restart | F8 partner teams | F9/F11 partner modes | F10 HP→29% | F12 practice/match"
	_help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_help.position = Vector2(12, -52)
	_help.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	add_child(_help)


func _log_event(s: String) -> void:
	_events.push_front("%6.2f  %s" % [Time.get_ticks_msec() / 1000.0, s])
	if _events.size() > 6:
		_events.resize(6)


func _process(_delta: float) -> void:
	_overlay.queue_redraw()
	if motor == null or not _panel.visible:
		return
	var v := motor.velocity
	var h := motor.get_horizontal_velocity().length()
	var hag := motor.get_height_above_ground()
	var lines: PackedStringArray = []
	lines.append("PROFILE  %s" % motor.profile.display_name)
	lines.append("MOTION   %s  (%.2fs)%s" % [motor.get_state_name(), motor.state_time,
		"  [hover engaged]" if motor.hover_engaged else ""])
	lines.append("COMBAT   %s  HP %.0f/%.0f%s" % [combat.get_state_name(), combat.health.hp, combat.health.max_hp,
		("  ULT %s" % combat.ultimate.get_phase_name()) if combat.ultimate else ""])
	lines.append("VEL      (%.1f, %.1f, %.1f)  |h| %.1f  v %.1f m/s" % [v.x, v.y, v.z, h, v.y])
	lines.append("EN       %.1f / %.0f" % [motor.en, motor.profile.max_en])
	lines.append("HEIGHT   feet y %.2f  above ground %s  ceiling %.1f" % [motor.global_position.y,
		("%.2f" % hag) if hag != INF else "∞", motor.get_ascent_ceiling()])
	lines.append("AIR TIME %.2fs" % motor.air_time)
	lines.append("COLLIDE  floor:%s wall:%s ceil:%s  %s" % [_yn(motor.is_on_floor()), _yn(motor.is_on_wall()),
		_yn(motor.is_on_ceiling()), ",".join(motor.last_collisions)])
	if targeting.has_target():
		var tp := targeting.get_target_point()
		lines.append("LOCK     %s  dist %.1f  Δh %+.1f%s" % [targeting.current.name,
			motor.global_position.distance_to(tp), tp.y - motor.global_position.y,
			"  OCCLUDED %.1fs" % targeting.occluded_time if targeting.occluded_time > 0 else ""])
	else:
		lines.append("LOCK     none%s" % ("  (last: %s)" % targeting.last_lost_reason if targeting.last_lost_reason != "" else ""))
	lines.append("CAMERA   dist %.1f m (preset %d/%d)  fov %.1f  occluded:%s" % [rig.distance, rig.distance_preset_index + 1,
		rig.distance_presets.size(), rig.camera.fov, _yn(rig.occluded)])
	var mods := motor.get_modifier_descriptions()
	lines.append("MODS     %s" % (", ".join(mods) if not mods.is_empty() else "-"))
	lines.append("INCOMING hits %d  dodged %d  %s" % [TestProjectile.hits, TestProjectile.dodges, TestProjectile.last_result])
	lines.append("FPS      %d" % Engine.get_frames_per_second())
	lines.append("")
	lines.append_array(_events)
	lines.append("— damage log —")
	lines.append_array(CombatEvents.log_lines)
	_label.text = "\n".join(lines)
	_en_bar.max_value = motor.profile.max_en
	_en_bar.value = motor.en


func toggle_panel() -> void:
	_panel.visible = not _panel.visible
	_help.visible = _panel.visible


func _yn(b: bool) -> String:
	return "Y" if b else "n"


func _draw_overlay() -> void:
	if rig == null or rig.camera == null or motor == null:
		return
	var cam := rig.camera
	var vp := _overlay.get_viewport_rect().size
	var center := vp * 0.5
	var margin := 40.0
	if vp.x < margin * 4.0 or vp.y < margin * 4.0:
		return
	# velocity vector projected from the mech's chest
	var chest := motor.global_position + Vector3.UP * 2.5
	if not cam.is_position_behind(chest):
		var a := cam.unproject_position(chest)
		var tip_w := chest + motor.velocity * 0.25
		if not cam.is_position_behind(tip_w):
			_overlay.draw_line(a, cam.unproject_position(tip_w), Color(0.3, 1.0, 0.4), 3.0)
	for t in TeamRules.get_valid_targets(motor):
		var p := targeting.get_target_point(t)
		var locked := t == targeting.current
		var col := Color(1.0, 0.85, 0.1) if locked else Color(1.0, 0.3, 0.25)
		var behind := cam.is_position_behind(p)
		var sp := cam.unproject_position(p)
		var on_screen := not behind and Rect2(Vector2.ZERO, vp).grow(-margin).has_point(sp)
		if on_screen:
			if locked:
				_overlay.draw_arc(sp, 26.0, 0, TAU, 32, col, 3.0)
				var tt := t as TestTarget
				if tt and tt.telegraphing:
					_overlay.draw_arc(sp, 36.0, 0, TAU, 32, Color(1, 0.1, 0.1), 4.0)
			continue
		# off-screen indicator on the screen edge
		var dir := (sp - center)
		if behind:
			dir = -dir
		if dir.length() < 1.0:
			dir = Vector2(0, 1)
		dir = dir.normalized()
		var half := center - Vector2(margin, margin)
		var s := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
		var pos := center + dir * s
		var perp := Vector2(-dir.y, dir.x)
		var size := 16.0 if locked else 12.0
		_overlay.draw_colored_polygon(PackedVector2Array([pos + dir * size, pos - dir * size * 0.6 + perp * size * 0.7,
			pos - dir * size * 0.6 - perp * size * 0.7]), col)
		var dh := p.y - motor.global_position.y
		var dist := motor.global_position.distance_to(p)
		var arrow := "▲" if dh > 3.0 else ("▼" if dh < -3.0 else "")
		_overlay.draw_string(UiFont.get_font(), pos - dir * 34.0 + Vector2(-24, 5), "%s%.0fm" % [arrow, dist],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
